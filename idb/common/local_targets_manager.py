#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import logging
import os
from typing import List

from idb.common.constants import IDB_LOCAL_TARGETS_FILE
from idb.common.format import target_description_from_dictionary
from idb.common.types import TargetDescription


# this is the new companion manager for direct_client mode


class LocalTargetsManager:
    def __init__(
        self, logger: logging.Logger, local_targets_file: str = IDB_LOCAL_TARGETS_FILE
    ) -> None:
        self.local_targets: List[TargetDescription] = []
        self.local_targets_file = local_targets_file
        self.logger = logger
        self.logger.info(f"idb local targets file stored at {self.local_targets_file}")

    def get_local_targets(self) -> List[TargetDescription]:
        self.local_targets = self._load()
        return self.local_targets

    def _load(self) -> List[TargetDescription]:
        targets = []
        if (
            os.path.exists(self.local_targets_file)
            and os.path.getsize(self.local_targets_file) > 0
        ):
            with open(self.local_targets_file, "r") as f:
                targets_list = json.load(f)
                for target in targets_list:
                    targets.append(target_description_from_dictionary(target))
        return targets

    def is_local_target_available(self, target_udid: str) -> bool:
        self.get_local_targets()
        targets = []
        targets = [
            target for target in self.local_targets if target.udid == target_udid
        ]
        return len(targets) > 0

    def clear(self) -> None:
        with open(self.local_targets_file, "w") as f:
            json.dump([], f)
            f.flush()
