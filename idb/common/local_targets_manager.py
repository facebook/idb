#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import logging
import os
from typing import List

import aiofiles
from idb.common.constants import IDB_LOCAL_TARGETS_FILE
from idb.common.format import target_description_from_dictionary
from idb.common.types import TargetDescription


class LocalTargetsManager:
    def __init__(
        self, logger: logging.Logger, local_targets_file: str = IDB_LOCAL_TARGETS_FILE
    ) -> None:
        self._local_targets_file = local_targets_file
        self._logger = logger

    async def get_local_targets(self) -> List[TargetDescription]:
        if not os.path.exists(self._local_targets_file):
            self._logger.debug(
                f"No local targets file at {self._local_targets_file} to read"
            )
            return []
        if os.path.getsize(self._local_targets_file) < 1:
            self._logger.debug(f"Empty targets file at {self._local_targets_file}")
        async with aiofiles.open(self._local_targets_file, "r") as f:
            line = (await f.readline()).strip()
            self._logger.debug(f"Read targets {line} from {self._local_targets_file}")
            return [
                target_description_from_dictionary(target)
                for target in json.loads(line)
            ]

    async def is_local_target_available(self, target_udid: str) -> bool:
        all_targets = await self.get_local_targets()
        filtered_targets = [
            target for target in all_targets if target.udid == target_udid
        ]
        return len(filtered_targets) > 0

    async def clear(self) -> None:
        async with aiofiles.open(self._local_targets_file, "w") as f:
            await f.write(json.dumps([]))
