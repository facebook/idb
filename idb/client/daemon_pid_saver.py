#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
import logging
import os
import signal
from typing import List

from idb.common.constants import IDB_DAEMON_PID_PATH


def save_daemon_pid(pid: int) -> None:
    pids = _get_daemon_pids()
    pids.append(pid)
    _write_daemon_pids(pids=pids)
    logging.debug(f"saved daemon pid {pid}")


def remove_daemon_pid(pid: int) -> None:
    pids = _get_daemon_pids()
    if pids.count(pid) > 0:
        pids.remove(pid)
        _write_daemon_pids(pids=pids)
        logging.debug(f"removed daemon pid {pid}")


def _write_daemon_pids(pids: List[int]) -> None:
    with open(IDB_DAEMON_PID_PATH, "w") as pid_file:
        json.dump(pids, pid_file)
        pid_file.flush()


def _has_saved_pids() -> bool:
    pids = _get_daemon_pids()
    logging.debug(f"has saved pids {pids}")
    return len(pids) > 0


def _get_daemon_pids() -> List[int]:
    try:
        with open(IDB_DAEMON_PID_PATH) as pid_file:
            return json.load(pid_file)
    except Exception:
        return []


def _clear_saved_daemon_pids() -> None:
    if os.path.exists(IDB_DAEMON_PID_PATH):
        # Empty the file
        with open(IDB_DAEMON_PID_PATH, "wb", buffering=0) as pid_file:
            pid_file.flush()


async def kill_saved_pids() -> None:
    if not _has_saved_pids():
        logging.debug(f"no daemon pid found")
        return
    for pid in _get_daemon_pids():
        try:
            os.kill(pid, signal.SIGTERM)
            logging.info(f"stopped daemon with pid {pid}")
        except OSError:
            logging.exception(f"failed to stop daemon with pid {pid} because of error")
    _clear_saved_daemon_pids()
