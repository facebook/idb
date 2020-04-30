#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from datetime import timedelta
from typing import Any, Dict


# Subject to change
DEFAULT_DAEMON_PORT: int = 9888
DEFAULT_DAEMON_GRPC_PORT: int = 9889
DEFAULT_DAEMON_HOST: str = "localhost"
LONG_THRIFT_TIMEOUT: float = timedelta(hours=2).total_seconds()
LOG_POLL_INTERVAL: float = 1.0
TESTS_POLL_INTERVAL: float = 0.5
XCTEST_TIMEOUT: float = timedelta(hours=1).total_seconds()
INSTALL_TIMEOUT: float = timedelta(minutes=5).total_seconds()
START_INSTRUMENTS_TIMEOUT: float = timedelta(minutes=6).total_seconds()
STOP_INSTRUMENTS_TIMEOUT: float = timedelta(minutes=10).total_seconds()
CRASH_LIST_TIMEOUT: float = timedelta(minutes=5).total_seconds()

JSONDict = Dict[str, Any]

BASE_IDB_FILE_PATH: str = "/tmp/idb"
IDB_PID_PATH: str = f"{BASE_IDB_FILE_PATH}/pid"
IDB_LOGS_PATH: str = f"{BASE_IDB_FILE_PATH}/logs"
IDB_STATE_FILE_PATH: str = f"{BASE_IDB_FILE_PATH}/state"
IDB_LOCAL_TARGETS_FILE: str = f"{BASE_IDB_FILE_PATH}/targets"
