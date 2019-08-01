#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import logging
import warnings
from typing import Dict, List, Optional

import idb.grpc.ipc_loader as ipc_loader
from grpclib.client import Channel
from grpclib.exceptions import GRPCError, ProtocolError, StreamTerminatedError
from idb.client.daemon_pid_saver import kill_saved_pids
from idb.client.daemon_spawner import DaemonSpawner
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.logging import log_call
from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    IdbClient,
    IdbException,
    InstalledAppInfo,
)
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import ListAppsRequest
from idb.grpc.types import CompanionClient


# this is to silence the channel not closed warning
# https://github.com/vmagamedov/grpclib/issues/58
warnings.filterwarnings(action="ignore", category=ResourceWarning)


def log_and_handle_exceptions(func):  # pyre-ignore
    @log_call(name=func.__name__)
    def func_wrapper(*args, **kwargs):  # pyre-ignore

        try:
            return func(*args, **kwargs)

        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    return func_wrapper


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
        self.daemon_channel: Optional[Channel] = None
        self.daemon_stub: Optional[CompanionServiceStub] = None
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
        if not self.daemon_channel or not self.daemon_stub:
            self.daemon_channel = Channel(
                self.host, self.port, loop=asyncio.get_event_loop()
            )
            self.daemon_stub = CompanionServiceStub(channel=self.daemon_channel)
        return CompanionClient(
            stub=self.daemon_stub,
            is_local=True,
            udid=self.target_udid,
            logger=self.logger,
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

    @log_and_handle_exceptions
    async def list_apps(self) -> List[InstalledAppInfo]:
        response = await self.stub.list_apps(ListAppsRequest())
        return [
            InstalledAppInfo(
                bundle_id=app.bundle_id,
                name=app.name,
                architectures=app.architectures,
                install_type=app.install_type,
                process_state=AppProcessState(app.process_state),
                debuggable=app.debuggable,
            )
            for app in response.apps
        ]
