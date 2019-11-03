#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import logging
import warnings
from typing import Dict, Optional

from idb.common.direct_companion_manager import DirectCompanionManager
from idb.grpc.idb_grpc import CompanionServiceBase


# Don't let the abstractmetod machineary mess raise at runtime
CompanionServiceBase.__abstractmethods__ = frozenset([])
# this is to silence the channel not closed warning
# https://github.com/vmagamedov/grpclib/issues/58
warnings.filterwarnings(action="ignore", category=ResourceWarning)


class GRPCHandler(CompanionServiceBase):
    def __init__(self, logger: Optional[logging.Logger] = None) -> None:
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_daemon")
        )
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)

    def get_udid(self, metadata: Dict[str, str]) -> Optional[str]:
        return metadata.get("udid")
