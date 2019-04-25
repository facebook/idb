#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from datetime import timedelta
from typing import Any, Dict


# Subject to change
DEFAULT_DAEMON_PORT = 9888
DEFAULT_DAEMON_GRPC_PORT = 9889
DEFAULT_DAEMON_HOST = "localhost"
LONG_THRIFT_TIMEOUT = timedelta(hours=2).total_seconds()
LOG_POLL_INTERVAL = 1.0
TESTS_POLL_INTERVAL = 0.5
XCTEST_TIMEOUT = timedelta(hours=1).total_seconds()
INSTALL_TIMEOUT = timedelta(minutes=5).total_seconds()
START_INSTRUMENTS_TIMEOUT = timedelta(minutes=2).total_seconds()
STOP_INSTRUMENTS_TIMEOUT = timedelta(minutes=10).total_seconds()
CRASH_LIST_TIMEOUT = timedelta(minutes=5).total_seconds()

JSONDict = Dict[str, Any]

IDB_DAEMON_PID_PATH = "/tmp/idb_daemon_pid"
IDB_LOGS_PATH = "/tmp/idb_logs"
