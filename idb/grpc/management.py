#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import logging
import os
import tempfile
from typing import AsyncContextManager, Dict, List, Optional

from idb.common.companion_spawner import CompanionSpawner
from idb.common.constants import BASE_IDB_FILE_PATH
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.local_targets_manager import LocalTargetsManager
from idb.common.logging import log_call
from idb.common.pid_saver import PidSaver
from idb.common.types import (
    Address,
    CompanionInfo,
    ConnectionDestination,
    IdbException,
    IdbManagementClient as IdbManagementClientBase,
    TargetDescription,
)
from idb.grpc.client import IdbClient
from idb.grpc.companion import merge_connected_targets
from idb.grpc.destination import destination_to_grpc
from idb.grpc.idb_pb2 import ConnectRequest
from idb.utils.contextlib import asynccontextmanager


class IdbManagementClient(IdbManagementClientBase):
    def __init__(
        self,
        companion_path: Optional[str] = None,
        device_set_path: Optional[str] = None,
        prune_dead_companion: bool = True,
        logger: Optional[logging.Logger] = None,
    ) -> None:
        os.makedirs(BASE_IDB_FILE_PATH, exist_ok=True)
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_grpc_client")
        )
        self.companion_path = companion_path
        self._prune_dead_companion = prune_dead_companion
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)
        self.local_targets_manager = LocalTargetsManager(logger=self.logger)

    async def _spawn_notifier(self) -> None:
        companion_path = self.companion_path
        if companion_path:
            companion_spawner = CompanionSpawner(
                companion_path=companion_path, logger=self.logger
            )
            await companion_spawner.spawn_notifier()

    async def _spawn_companion(self, target_udid: str) -> Optional[CompanionInfo]:
        companion_path = self.companion_path
        if companion_path is None:
            return None
        local_target_available = await self.local_targets_manager.is_local_target_available(
            target_udid=target_udid
        )
        if local_target_available or target_udid == "mac":
            companion_spawner = CompanionSpawner(
                companion_path=companion_path, logger=self.logger
            )
            self.logger.info(f"will attempt to spawn a companion for {target_udid}")
            port = await companion_spawner.spawn_companion(target_udid=target_udid)
            if port:
                self.logger.info(f"spawned a companion for {target_udid}")
                host = "localhost"
                companion_info = CompanionInfo(
                    host=host, port=port, udid=target_udid, is_local=True
                )
                await self.direct_companion_manager.add_companion(companion_info)
                return companion_info
        return None

    async def _companion_to_target(
        self, companion: CompanionInfo
    ) -> Optional[TargetDescription]:
        try:
            async with IdbClient.build(
                host=companion.host,
                port=companion.port,
                is_local=False,
                logger=self.logger,
            ) as client:
                return await client.describe()
        except Exception:
            if not self._prune_dead_companion:
                self.logger.warning(
                    f"Failed to describe {companion}, but not removing it"
                )
                return None
            self.logger.warning(f"Failed to describe {companion}, removing it")
            await self.direct_companion_manager.remove_companion(
                Address(host=companion.host, port=companion.port)
            )
            return None

    @asynccontextmanager
    async def from_udid(self, udid: Optional[str]) -> AsyncContextManager[IdbClient]:
        await self._spawn_notifier()
        try:
            companion_info = await self.direct_companion_manager.get_companion_info(
                target_udid=udid
            )
        except IdbException as e:
            # will try to spawn a companion if on mac.
            if udid is None:
                raise e
            companion_info = await self._spawn_companion(target_udid=udid)
            if companion_info is None:
                raise e
        async with IdbClient.build(
            host=companion_info.host,
            port=companion_info.port,
            is_local=companion_info.is_local,
            logger=self.logger,
        ) as client:
            yield client

    @log_call()
    async def list_targets(self) -> List[TargetDescription]:
        (_, companions, local_targets) = await asyncio.gather(
            self._spawn_notifier(),
            self.direct_companion_manager.get_companions(),
            self.local_targets_manager.get_local_targets(),
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
        self.logger.debug(f"Connecting directly to {destination} with meta {metadata}")
        if isinstance(destination, Address):
            async with IdbClient.build(
                host=destination.host,
                port=destination.port,
                is_local=False,
                logger=self.logger,
            ) as client:
                with tempfile.NamedTemporaryFile(mode="w+b") as f:
                    response = await client.stub.connect(
                        ConnectRequest(
                            destination=destination_to_grpc(destination),
                            metadata=metadata,
                            local_file_path=f.name,
                        )
                    )
            companion = CompanionInfo(
                udid=response.companion.udid,
                host=destination.host,
                port=destination.port,
                is_local=response.companion.is_local,
            )
            self.logger.debug(f"Connected directly to {companion}")
            await self.direct_companion_manager.add_companion(companion)
            return companion
        else:
            companion = await self._spawn_companion(target_udid=destination)
            if companion:
                return companion
            else:
                raise IdbException(f"can't find target for udid {destination}")

    @log_call()
    async def disconnect(self, destination: ConnectionDestination) -> None:
        await self.direct_companion_manager.remove_companion(destination)

    @log_call()
    async def kill(self) -> None:
        await self.direct_companion_manager.clear()
        await self.local_targets_manager.clear()
        PidSaver(logger=self.logger).kill_saved_pids()
