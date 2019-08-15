#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
import logging
import os
from fcntl import LOCK_EX, LOCK_UN, lockf
from typing import List, Optional

from idb.common.constants import IDB_STATE_FILE_PATH
from idb.common.format import json_data_companions, json_to_companion_info
from idb.common.types import CompanionInfo, ConnectionDestination, IdbException


# this is the new companion manager for direct_client mode


class DirectCompanionManager:
    def __init__(
        self, logger: logging.Logger, state_file_path: str = IDB_STATE_FILE_PATH
    ) -> None:
        self.companions: List[CompanionInfo] = []
        self.state_file_path = state_file_path
        self.logger = logger
        self.logger.info(f"idb state file stored at {self.state_file_path}")

    def add_companion(self, companion: CompanionInfo) -> None:
        if companion in self.companions:
            self.logger.info(f"companion {companion} already added")
        else:
            self.companions.append(companion)
            self.logger.info(f"added direct companion {companion}")
        self._save()

    def get_companions(self) -> List[CompanionInfo]:
        self.companions = self._load()
        return self.companions

    def _save(self) -> None:
        with open(self.state_file_path, "w") as f:
            lockf(f, LOCK_EX)
            json.dump(json_data_companions(self.companions), f)
            lockf(f, LOCK_UN)

    def _load(self) -> List[CompanionInfo]:
        if os.path.exists(self.state_file_path):
            with open(self.state_file_path, "r") as f:
                return json_to_companion_info(json.load(f))
        return []

    def clear(self) -> None:
        self.companions = []
        self._save()

    def get_companion_info(self, target_udid: Optional[str]) -> CompanionInfo:
        self.get_companions()
        if target_udid:
            companions = [
                companion
                for companion in self.companions
                if companion.udid == target_udid
            ]
            if len(companions) > 0:
                return companions[0]
            else:
                raise IdbException(
                    f"Couldn't find companion for target with udid {target_udid}"
                )
        elif len(self.companions) >= 1:
            companion = self.companions[0]
            self.logger.info(f"using default companion with udid {companion.udid}")
            return companion
        else:
            raise IdbException("No UDID provided and couldn't find a default companion")

    def remove_companion(self, destination: ConnectionDestination) -> None:
        self.get_companions()
        companions = []
        if isinstance(destination, str):
            companions = [
                companion
                for companion in self.companions
                if companion.udid == destination
            ]
        else:
            companions = [
                companion
                for companion in self.companions
                if companion.host == destination.host
                and companion.port == destination.port
            ]
        for companion in companions:
            self.companions.remove(companion)
        self._save()
