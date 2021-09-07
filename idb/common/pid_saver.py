#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import logging
import os
import signal
from typing import List

from idb.common.constants import IDB_PID_PATH


class PidSaver:
    def __init__(
        self, logger: logging.Logger, pids_file_path: str = IDB_PID_PATH
    ) -> None:
        self.companion_pids: List[int] = []
        self.logger = logger
        self.pids_file_path = pids_file_path

    def save_companion_pid(self, pid: int) -> None:
        self._load()
        self.companion_pids.append(pid)
        self._save()
        self.logger.info(f"saved companion pid {pid}")

    def _save(self) -> None:
        with open(self.pids_file_path, "w+") as pid_file:
            json.dump(
                {"companions": self.companion_pids},
                pid_file,
            )
            pid_file.flush()

    def _load(self) -> None:
        try:
            with open(self.pids_file_path) as pid_file:
                dictionary = json.load(pid_file)
                self.companion_pids = dictionary["companions"]
        except Exception as e:
            self.logger.info(
                f"failed to open pid file {self.pids_file_path} because of {e}"
            )

    def _clear_saved_pids(self) -> None:
        self.companion_pids = []
        self._save()

    def kill_saved_pids(self) -> None:
        self._load()
        for pid in list(self.companion_pids):
            try:
                os.kill(pid, signal.SIGTERM)
                self.logger.info(f"stopped with pid {pid}")
            except OSError or ProcessLookupError:
                pass
        self._clear_saved_pids()
