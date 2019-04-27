#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import logging
import warnings
from typing import Optional, Dict

import idb.grpc.ipc_loader as ipc_loader
from idb.common.boot_manager import BootManager
from idb.grpc.types import CompanionClient
from idb.manager.companion import CompanionManager
from idb.grpc.ipc_loader import DaemonContext
from idb.grpc.idb_grpc import CompanionServiceBase


# Don't let the abstractmetod machineary mess raise at runtime
CompanionServiceBase.__abstractmethods__ = frozenset([])
# this is to silence the channel not closed warning
# https://github.com/vmagamedov/grpclib/issues/58
warnings.filterwarnings(action="ignore", category=ResourceWarning)


class GRPCHandler(CompanionServiceBase):
    def __init__(
        self,
        companion_manager: CompanionManager,
        boot_manager: BootManager,
        logger: Optional[logging.Logger] = None,
    ) -> None:
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_daemon")
        )
        self.companion_manager = companion_manager
        self.boot_manager = boot_manager
        for (call_name, f) in ipc_loader.daemon_calls(
            companion_provider=self.provide_client,
            context_provider=self.provide_context,
        ):
            setattr(self, call_name, f)

    def get_udid(self, metadata: Dict[str, str]) -> Optional[str]:
        return metadata.get("udid")

    async def provide_client(self, udid: Optional[str]) -> CompanionClient:
        return await self.companion_manager.get_stub_for_udid(udid=udid)

    async def provide_context(self) -> DaemonContext:
        return DaemonContext(
            companion_manager=self.companion_manager, boot_manager=self.boot_manager
        )
