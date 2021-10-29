#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import logging
import os
from typing import AsyncGenerator, Dict, List, Optional

from idb.common.companion import Companion, CompanionServerConfig
from idb.common.companion_set import CompanionSet
from idb.common.constants import BASE_IDB_FILE_PATH
from idb.common.logging import log_call
from idb.common.types import (
    ClientManager as ClientManagerBase,
    CompanionInfo,
    OnlyFilter,
    ConnectionDestination,
    DomainSocketAddress,
    IdbException,
    TargetType,
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
        self._companion_set = CompanionSet(logger=self._logger)
        self._companion: Optional[Companion] = (
            Companion(
                companion_path=companion_path,
                device_set_path=device_set_path,
                logger=self._logger,
            )
            if companion_path is not None
            else None
        )
        self._prune_dead_companion = prune_dead_companion

    async def _spawn_companion_server(self, udid: str) -> Optional[CompanionInfo]:
        companion = self._companion
        if companion is None:
            return None
        target_type = await self._local_target_type(udid=udid)
        if target_type is None:
            return None
        self._logger.info(f"will attempt to spawn a companion for {udid}")
        (process, port) = await companion.spawn_tcp_server(
            config=CompanionServerConfig(
                udid=udid,
                only=target_type,
                log_file_path=None,
                cwd=None,
                tmp_path=None,
                reparent=True,
            ),
            port=None,
        )
        self._logger.info(f"Companion at port {port} spawned for {udid}")
        host = "localhost"
        companion_info = CompanionInfo(
            address=TCPAddress(host=host, port=port),
            udid=udid,
            is_local=True,
            pid=process.pid,
        )
        await self._companion_set.add_companion(companion_info)
        return companion_info

    async def _list_local_targets(
        self, only: Optional[OnlyFilter]
    ) -> List[TargetDescription]:
        companion = self._companion
        if companion is None:
            return []
        return await companion.list_targets(only=only)

    async def _local_target_type(self, udid: str) -> Optional[TargetType]:
        if udid == "mac":
            return TargetType.MAC
        targets = {
            target.udid: target for target in await self._list_local_targets(only=None)
        }
        target = targets.get(udid)
        if target is None:
            return None
        return target.target_type

    async def _companion_to_target(
        self, companion: CompanionInfo
    ) -> Optional[TargetDescription]:
        try:
            async with Client.build(
                address=companion.address, logger=self._logger
            ) as client:
                return await client.describe()
        except Exception:
            if not self._prune_dead_companion:
                self._logger.warning(
                    f"Failed to describe {companion}, but not removing it"
                )
                return None
            self._logger.warning(f"Failed to describe {companion}, removing it")
            await self._companion_set.remove_companion(companion.address)
            return None

    @asynccontextmanager
    async def from_udid(self, udid: Optional[str]) -> AsyncGenerator[Client, None]:
        try:
            companion_info = await self._companion_set.get_companion_info(
                target_udid=udid
            )
            self._logger.debug(f"Got existing companion {companion_info}")
            async with Client.build(
                address=companion_info.address,
                logger=self._logger,
            ) as client:
                self._logger.debug(f"Constructed client for companion {udid}")
                yield client
        except IdbException as e:
            self._logger.debug(f"No companion info for {udid}, spawning one...")
            # will try to spawn a companion if on mac.
            if udid is None:
                raise e
            companion_info = await self._spawn_companion_server(udid=udid)
            if companion_info is None:
                raise e
            self._logger.debug(f"Got newly launched {companion_info} for udid {udid}")
            async with Client.build(
                address=companion_info.address,
                logger=self._logger,
            ) as client:
                self._logger.debug(f"Constructed client for companion {udid}")
                yield client

    @log_call()
    async def list_targets(
        self, only: Optional[OnlyFilter] = None
    ) -> List[TargetDescription]:
        (companions, local_targets) = await asyncio.gather(
            self._companion_set.get_companions(),
            self._list_local_targets(only=only),
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
            async with Client.build(address=destination, logger=self._logger) as client:
                companion = client.companion
            self._logger.debug(f"Connected directly to {companion}")
            await self._companion_set.add_companion(companion)
            return companion
        else:
            companion = await self._spawn_companion_server(udid=destination)
            if companion:
                return companion
            else:
                raise IdbException(f"can't find target for udid {destination}")

    @log_call()
    async def disconnect(self, destination: ConnectionDestination) -> None:
        await self._companion_set.remove_companion(destination)

    @log_call()
    async def kill(self) -> None:
        await self._companion_set.clear()
