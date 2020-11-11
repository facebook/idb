#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import logging
import os
from typing import AsyncGenerator, Dict, List, Optional

from idb.common.companion_spawner import CompanionSpawner
from idb.common.constants import BASE_IDB_FILE_PATH
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.local_targets_manager import LocalTargetsManager
from idb.common.logging import log_call
from idb.common.pid_saver import PidSaver
from idb.common.types import (
    ClientManager as ClientManagerBase,
    CompanionInfo,
    ConnectionDestination,
    DomainSocketAddress,
    IdbException,
    TargetDescription,
    TCPAddress,
)
from idb.grpc.client import Client
from idb.grpc.target import merge_connected_targets
from idb.utils.contextlib import asynccontextmanager


class ClientManager(ClientManagerBase):
    def __init__(
        self,
        companion_path: Optional[str] = None,
        device_set_path: Optional[str] = None,
        prune_dead_companion: bool = True,
        logger: Optional[logging.Logger] = None,
    ) -> None:
        os.makedirs(BASE_IDB_FILE_PATH, exist_ok=True)
        self._logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_grpc_client")
        )
        self._direct_companion_manager = DirectCompanionManager(logger=self._logger)
        self._local_targets_manager = LocalTargetsManager(logger=self._logger)
        self._companion_spawner: Optional[CompanionSpawner] = (
            CompanionSpawner(companion_path=companion_path, logger=self._logger)
            if companion_path is not None
            else None
        )
        self._prune_dead_companion = prune_dead_companion

    async def _spawn_notifier(self) -> None:
        companion_spawner = self._companion_spawner
        if companion_spawner is None:
            return
        await companion_spawner.spawn_notifier()

    async def _spawn_companion(self, target_udid: str) -> Optional[CompanionInfo]:
        companion_spawner = self._companion_spawner
        if companion_spawner is None:
            return None
        local_target_available = (
            await self._local_targets_manager.is_local_target_available(
                target_udid=target_udid
            )
        )
        if local_target_available or target_udid == "mac":
            self._logger.info(f"will attempt to spawn a companion for {target_udid}")
            port = await companion_spawner.spawn_companion(target_udid=target_udid)
            if port:
                self._logger.info(f"spawned a companion for {target_udid}")
                host = "localhost"
                companion_info = CompanionInfo(
                    address=TCPAddress(host=host, port=port),
                    udid=target_udid,
                    is_local=True,
                )
                await self._direct_companion_manager.add_companion(companion_info)
                return companion_info
        return None

    async def _companion_to_target(
        self, companion: CompanionInfo
    ) -> Optional[TargetDescription]:
        try:
            async with Client.build(
                address=companion.address, is_local=False, logger=self._logger
            ) as client:
                return await client.describe()
        except Exception:
            if not self._prune_dead_companion:
                self._logger.warning(
                    f"Failed to describe {companion}, but not removing it"
                )
                return None
            self._logger.warning(f"Failed to describe {companion}, removing it")
            await self._direct_companion_manager.remove_companion(companion.address)
            return None

    @asynccontextmanager
    async def from_udid(self, udid: Optional[str]) -> AsyncGenerator[Client, None]:
        await self._spawn_notifier()
        try:
            companion_info = await self._direct_companion_manager.get_companion_info(
                target_udid=udid
            )
            self._logger.debug(f"Got existing companion {companion_info}")
            async with Client.build(
                address=companion_info.address,
                is_local=companion_info.is_local,
                logger=self._logger,
            ) as client:
                self._logger.debug(f"Constructed client for companion {udid}")
                yield client
        except IdbException as e:
            self._logger.debug(f"No companion info for {udid}, spawning one...")
            # will try to spawn a companion if on mac.
            if udid is None:
                raise e
            companion_info = await self._spawn_companion(target_udid=udid)
            if companion_info is None:
                raise e
            self._logger.debug(f"Got newly launched {companion_info} for udid {udid}")
            async with Client.build(
                address=companion_info.address,
                is_local=companion_info.is_local,
                logger=self._logger,
            ) as client:
                self._logger.debug(f"Constructed client for companion {udid}")
                yield client

    @log_call()
    async def list_targets(self) -> List[TargetDescription]:
        await self._spawn_notifier()
        (companions, local_targets) = await asyncio.gather(
            self._direct_companion_manager.get_companions(),
            self._local_targets_manager.get_local_targets(),
        )
        connected_targets = [
            target
            for target in (
                await asyncio.gather(
                    *(
                        self._companion_to_target(companion=companion)
                        for companion in companions
                    )
                )
            )
            if target is not None
        ]
        return merge_connected_targets(
            local_targets=local_targets, connected_targets=connected_targets
        )

    @log_call()
    async def connect(
        self,
        destination: ConnectionDestination,
        metadata: Optional[Dict[str, str]] = None,
    ) -> CompanionInfo:
        self._logger.debug(f"Connecting directly to {destination} with meta {metadata}")
        if isinstance(destination, TCPAddress) or isinstance(
            destination, DomainSocketAddress
        ):
            async with Client.build(
                address=destination, is_local=False, logger=self._logger
            ) as client:
                companion = client.companion
            self._logger.debug(f"Connected directly to {companion}")
            await self._direct_companion_manager.add_companion(companion)
            return companion
        else:
            companion = await self._spawn_companion(target_udid=destination)
            if companion:
                return companion
            else:
                raise IdbException(f"can't find target for udid {destination}")

    @log_call()
    async def disconnect(self, destination: ConnectionDestination) -> None:
        await self._direct_companion_manager.remove_companion(destination)

    @log_call()
    async def kill(self) -> None:
        await self._direct_companion_manager.clear()
        await self._local_targets_manager.clear()
        PidSaver(logger=self._logger).kill_saved_pids()
