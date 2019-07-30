#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import logging
import warnings
from typing import Dict, Optional

import idb.grpc.ipc_loader as ipc_loader
from grpclib.client import Channel
from idb.client.daemon_pid_saver import kill_saved_pids
from idb.client.daemon_spawner import DaemonSpawner
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.types import CompanionInfo, IdbClient, IdbException
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.types import CompanionClient


# this is to silence the channel not closed warning
# https://github.com/vmagamedov/grpclib/issues/58
warnings.filterwarnings(action="ignore", category=ResourceWarning)


class GrpcClient(IdbClient):
    def __init__(
        self,
        port: int,
        host: str,
        target_udid: Optional[str],
        logger: Optional[logging.Logger] = None,
        force_kill_daemon: bool = False,
    ) -> None:
        self.port: int = port
        self.host: str = host
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_grpc_client")
        )
        self.force_kill_daemon = force_kill_daemon
        self.target_udid = target_udid
        self.daemon_spawner = DaemonSpawner(host=self.host, port=self.port)
        self.channel: Optional[Channel] = None
        self.stub: Optional[CompanionServiceStub] = None
        for (call_name, f) in ipc_loader.client_calls(
            daemon_provider=self.provide_client
        ):
            setattr(self, call_name, f)
        # this is temporary while we are killing the daemon
        # the cli needs access to the new direct_companion_manager to route direct
        # commands.
        # this overrides the stub to talk directly to the companion
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)
        try:
            self.companion_info: CompanionInfo = self.direct_companion_manager.get_companion_info(
                target_udid=self.target_udid
            )
            self.logger.info(f"using companion {self.companion_info}")
            self.channel = Channel(
                self.companion_info.host,
                self.companion_info.port,
                loop=asyncio.get_event_loop(),
            )
            self.stub: CompanionServiceStub = CompanionServiceStub(channel=self.channel)
        except IdbException as e:
            self.logger.info(e)

    async def provide_client(self) -> CompanionClient:
        await self.daemon_spawner.start_daemon_if_needed(
            force_kill=self.force_kill_daemon
        )
        if not self.channel or not self.stub:
            self.channel = Channel(self.host, self.port, loop=asyncio.get_event_loop())
            self.stub = CompanionServiceStub(channel=self.channel)
        return CompanionClient(
            stub=self.stub, is_local=True, udid=self.target_udid, logger=self.logger
        )

    @property
    def metadata(self) -> Dict[str, str]:
        if self.target_udid:
            return {"udid": self.target_udid}
        else:
            return {}

    @classmethod
    async def kill(cls) -> None:
        await kill_saved_pids()
