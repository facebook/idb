#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import tempfile
from logging import Logger
from typing import AsyncContextManager, Dict, List, Optional

from grpclib.client import Channel
from idb.grpc.types import CompanionClient
from idb.common.companion_spawner import CompanionSpawner
from idb.common.types import (
    Address,
    CompanionInfo,
    ConnectionDestination,
    TargetDescription,
)
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import ConnectRequest
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


class CompanionManager:
    def __init__(self, companion_path: Optional[str], logger: Logger) -> None:
        self._udid_companion_map: Dict[str, CompanionInfo] = {}
        self._udid_target_map: Dict[str, TargetDescription] = {}
        self.companion_spawner = (
            CompanionSpawner(companion_path=companion_path) if companion_path else None
        )
        self._stub_map: Dict[str, CompanionServiceStub] = {}
        self._logger = logger

    def close(self) -> None:
        self._logger.info("Stopping companion manager")
        if self.companion_spawner:
            self.companion_spawner.close()

    def is_companion_available_for_target_udid(self, target_udid: str) -> bool:
        return target_udid in self._udid_target_map

    def add_companion(self, companion: CompanionInfo) -> None:
        self._udid_companion_map[companion.udid] = companion
        self._logger.info(f"Added a companion: {companion}")
        if companion.udid in self._udid_target_map:
            target = self._udid_target_map[companion.udid]
            self._udid_target_map[companion.udid] = TargetDescription(
                udid=target.udid,
                name=target.name,
                state=target.state,
                target_type=target.target_type,
                os_version=target.os_version,
                architecture=target.architecture,
                companion_info=companion,
                screen_dimensions=target.screen_dimensions,
            )
            self._logger.info(f"Assigned the companion to target: {companion.udid}")
        else:
            self._udid_target_map[companion.udid] = TargetDescription(
                udid=companion.udid,
                name="",
                state=None,
                target_type=None,
                os_version=None,
                architecture=None,
                companion_info=companion,
                screen_dimensions=None,
            )

    def remove_companion(
        self, destination: ConnectionDestination
    ) -> Optional[CompanionInfo]:
        self._logger.info(f"Removing companion {destination}")
        if isinstance(destination, Address):
            host = destination.host
            port = destination.port
            for companion in self._udid_companion_map.values():
                if companion.port == port and companion.host == host:
                    del self._udid_companion_map[companion.udid]
                    del self._udid_target_map[companion.udid]
                    self._logger.info(
                        f"Removed a companion at host: {host} port: {port}"
                    )
                    return companion
            self._logger.error(f"Did not found a companion at host {host} port: {port}")
        elif isinstance(destination, str):
            target_udid = destination
            if target_udid in self._udid_companion_map:
                companion = self._udid_companion_map[target_udid]
                del self._udid_companion_map[target_udid]
                del self._udid_target_map[target_udid]
                self._logger.info(f"Removed a companion: {target_udid}")
                return companion
            else:
                self._logger.error(f"Did not find a companion: {target_udid}")
        return None

    @property
    def targets(self) -> List[TargetDescription]:
        return [
            TargetDescription(
                udid=target.udid,
                state=target.state,
                target_type=target.target_type,
                name=target.name or "",
                os_version=target.os_version,
                architecture=target.architecture,
                companion_info=target.companion_info,
                screen_dimensions=None,
            )
            for target in self._udid_target_map.values()
        ]

    def update_target(self, target: TargetDescription) -> None:
        self._udid_target_map[target.udid] = target

    def has_default_companion(self) -> bool:
        return len(self._udid_companion_map) == 1

    def get_default_companion(self) -> CompanionInfo:
        return next(iter(self._udid_companion_map.values()))

    def _get_companion_for_target(
        self, target_udid: Optional[str], timeout: Optional[float] = None
    ) -> Optional[CompanionInfo]:
        self._logger.debug(f"fetching companion for {target_udid}")
        if target_udid:
            if target_udid in self._udid_companion_map:
                return self._udid_companion_map[target_udid]
            self._logger.debug(f"no companion available for {target_udid}")
        elif self.has_default_companion():
            self._logger.info("using default companion")
            return self.get_default_companion()
        return None

    @asynccontextmanager  # noqa T484
    async def create_companion_for_target_with_destination(
        self,
        destination: ConnectionDestination,
        metadata: Optional[Dict[str, str]] = None,
        timeout: Optional[float] = None,
    ) -> AsyncContextManager[CompanionInfo]:
        if isinstance(destination, Address):
            async with self.create_companion_for_target_with_address(
                address=destination, metadata=metadata, timeout=timeout
            ) as companion:
                yield companion
        else:
            async with self.create_companion_for_target_with_udid(
                target_udid=destination, metadata=metadata, timeout=timeout
            ) as companion:
                yield companion

    @asynccontextmanager  # noqa T484
    async def create_companion_for_target_with_address(
        self,
        address: Address,
        metadata: Optional[Dict[str, str]] = None,
        timeout: Optional[float] = None,
    ) -> AsyncContextManager[CompanionInfo]:
        try:
            yield await self._get_companion_info(address, metadata, timeout)
        except OSError as error:
            raise Exception(
                f"Failed to connect to companion at "
                f"{address.host}:{address.port} found error {error}"
            )

    async def _get_companion_info(
        self,
        address: Address,
        metadata: Optional[Dict[str, str]] = None,
        timeout: Optional[float] = None,
    ) -> CompanionInfo:
        stub = self.get_stub_for_address(address.host, none_throws(address.grpc_port))
        with tempfile.NamedTemporaryFile(mode="w+b") as file:
            response = await stub.connect(
                ConnectRequest(metadata=metadata, local_file_path=file.name)
            )
        info = CompanionInfo(
            udid=response.companion.udid,
            host=address.host,
            port=address.port,
            is_local=response.companion.is_local,
            grpc_port=address.grpc_port,
        )
        self.add_companion(info)
        return info

    @asynccontextmanager  # noqa T484
    async def create_companion_for_target_with_udid(
        self,
        target_udid: Optional[str],
        metadata: Optional[Dict[str, str]] = None,
        timeout: Optional[float] = None,
    ) -> AsyncContextManager[CompanionInfo]:
        self._logger.debug(f"getting companion for {target_udid}")
        companion = self._get_companion_for_target(target_udid=target_udid)
        if companion:
            yield companion
        elif target_udid is None:
            raise Exception("Please provide a UDID for your target")
        elif self.companion_spawner and target_udid in self._udid_target_map:
            self._logger.debug(f"spawning a companion for {target_udid}")
            port = await self.companion_spawner.spawn_companion(target_udid=target_udid)
            # overriding host here with localhost as spawning
            # the companion only works locally
            host = "localhost"
            self._logger.info(f"companion started at {host}:{port}")
            async with self.create_companion_for_target_with_address(
                address=Address(host=host, port=port, grpc_port=port),
                metadata=metadata,
                timeout=timeout,
            ) as companion:
                yield companion
        else:
            raise Exception(f"no companion available for {target_udid}")

    async def get_stub_for_udid(self, udid: Optional[str]) -> CompanionClient:
        is_companion_available = (
            self.is_companion_available_for_target_udid(udid) if udid else False
        )
        if udid and udid in self._stub_map and udid in self._udid_companion_map:
            return CompanionClient(
                stub=self._stub_map[udid],
                is_local=self._udid_companion_map[udid].is_local,
                udid=udid,
                logger=self._logger,
                is_companion_available=is_companion_available,
            )
        else:
            async with self.create_companion_for_target_with_udid(
                target_udid=udid
            ) as companion:
                stub = self.get_stub_for_address(
                    companion.host, none_throws(companion.grpc_port)
                )
                self._stub_map[companion.udid] = stub
                return CompanionClient(
                    stub=stub,
                    is_local=companion.is_local,
                    udid=udid,
                    logger=self._logger,
                    is_companion_available=is_companion_available,
                )

    def get_stub_for_address(self, host: str, port: int) -> CompanionServiceStub:
        self._logger.debug(f"creating grpc stub for companion at {host}:{port}")
        channel = Channel(host, port, loop=asyncio.get_event_loop())
        return CompanionServiceStub(channel)
