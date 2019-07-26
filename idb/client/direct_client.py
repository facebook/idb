#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import logging
from typing import Optional

from idb.common.types import IdbClient


class GrpcDirectClient(IdbClient):
    def __init__(self, logger: logging.Logger, target_udid: Optional[str]) -> None:
        self.logger = logger
        self.target_udid = target_udid
