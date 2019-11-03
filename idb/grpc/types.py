#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from logging import Logger
from typing import NamedTuple, Optional

from idb.grpc.idb_grpc import CompanionServiceStub


class CompanionClient(NamedTuple):
    stub: CompanionServiceStub
    is_local: bool
    udid: Optional[str]
    logger: Logger
    is_companion_available: bool = False
