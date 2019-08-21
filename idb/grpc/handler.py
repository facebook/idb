#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import logging
import warnings
from typing import Dict, Optional

from idb.common.boot_manager import BootManager
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.grpc.idb_grpc import CompanionServiceBase
from idb.manager.companion import CompanionManager


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
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)

    def get_udid(self, metadata: Dict[str, str]) -> Optional[str]:
        return metadata.get("udid")
