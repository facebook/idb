#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from datetime import timedelta
from typing import Any


# Subject to change
LONG_THRIFT_TIMEOUT: float = timedelta(hours=2).total_seconds()
LOG_POLL_INTERVAL: float = 1.0
TESTS_POLL_INTERVAL: float = 0.5
INSTALL_TIMEOUT: float = timedelta(minutes=5).total_seconds()
START_INSTRUMENTS_TIMEOUT: float = timedelta(minutes=6).total_seconds()
STOP_INSTRUMENTS_TIMEOUT: float = timedelta(minutes=10).total_seconds()
CRASH_LIST_TIMEOUT: float = timedelta(minutes=5).total_seconds()

JSONDict = dict[str, Any]

BASE_IDB_FILE_PATH: str = "/tmp/idb"
IDB_PID_PATH: str = f"{BASE_IDB_FILE_PATH}/pid"
IDB_LOGS_PATH: str = f"{BASE_IDB_FILE_PATH}/logs"
IDB_STATE_FILE_PATH: str = f"{BASE_IDB_FILE_PATH}/state"
