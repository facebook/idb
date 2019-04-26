#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import json
import logging
import os
import platform
import sys
from asyncio import StreamReader
from typing import List

import idb.common.networking as networking
from idb.client.daemon_pid_saver import kill_saved_pids, save_daemon_pid
from idb.common.constants import (
    DEFAULT_DAEMON_HOST,
    DEFAULT_DAEMON_GRPC_PORT,
    IDB_LOGS_PATH,
)
from idb.utils.typing import none_throws


class DaemonSpawnerException(Exception):
    pass


class DaemonSpawner:
    def __init__(self, port: int, host: str) -> None:
        self.port: int = port
        self.host: str = host

    async def start_daemon_if_needed(self, force_kill: bool = False) -> None:
        if self.port != DEFAULT_DAEMON_GRPC_PORT or self.host != DEFAULT_DAEMON_HOST:
            # don't spawn a daemon if there's any overrides
            return
        if not networking.is_port_open(self.host, self.port):
            await self._spawn_daemon()
        elif force_kill:
            await kill_saved_pids()
            await self._spawn_daemon()

    async def _read_daemon_output(self, stream: StreamReader) -> None:
        line = await stream.readline()
        try:
            json.loads(line.decode())
        except json.decoder.JSONDecodeError as e:
            raise DaemonSpawnerException(f"Failed to spawn daemon: {line}") from e

    def _log_file_path(self) -> str:
        os.makedirs(name=IDB_LOGS_PATH, exist_ok=True)
        return IDB_LOGS_PATH + "/daemon"

    async def _spawn_daemon(self) -> None:
        cmd: List[str] = [sys.argv[0], "daemon"]
        if platform.system() == "Darwin":
            logging.debug("Mac Detected. passing notifier path to daemon")
            cmd.extend(["--notifier-path", "idb_companion"])
        with open(self._log_file_path(), "w") as log_file:
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=log_file
            )
            logging.debug(f"daemon process id {process.pid}")
            save_daemon_pid(pid=process.pid)
            await self._read_daemon_output(none_throws(process.stdout))
