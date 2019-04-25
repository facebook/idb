#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from logging import Logger
from typing import NamedTuple, Optional

from idb.grpc.idb_grpc import CompanionServiceStub


class CompanionClient(NamedTuple):
    stub: CompanionServiceStub
    is_local: bool
    udid: Optional[str]
    logger: Logger
    is_companion_available: bool = False
