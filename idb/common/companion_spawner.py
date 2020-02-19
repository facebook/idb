#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import errno
import json
import logging
import os
from typing import List, Optional, Tuple

from idb.common.constants import IDB_LOCAL_TARGETS_FILE, IDB_LOGS_PATH
from idb.common.file import get_last_n_lines
from idb.common.pid_saver import PidSaver
from idb.utils.typing import none_throws


class CompanionSpawnerException(Exception):
    pass


async def _extract_port_from_spawned_companion(
    stream: asyncio.StreamReader
) -> Optional[int]:
    # The first line of stdout should contain launch info, otherwise something bad has happened
    line = await stream.readline()
    logging.debug(f"read line from companion : {line}")
    if line is None:
        return None
    update = json.loads(line.decode())
    logging.debug(f"got update from companion {update}")
    return update["grpc_port"]


async def do_spawn_companion(
    path: str,
    udid: str,
    log_file_path: str,
    device_set_path: Optional[str],
    port: Optional[int],
    cwd: Optional[str],
) -> Tuple[asyncio.subprocess.Process, int]:
    arguments: List[str] = [
        path,
        "--udid",
        udid,
        "--grpc-port",
        str(port) if port is not None else "0",
    ]
    if device_set_path is not None:
        arguments.extend(["--device-set-path", device_set_path])

    with open(log_file_path, "a") as log_file:
        process = await asyncio.create_subprocess_exec(
            *arguments,
            stdout=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.PIPE,
            stderr=log_file,
            cwd=cwd,
        )
        logging.debug(f"started companion at process id {process.pid}")
        stdout = none_throws(process.stdout)
        extracted_port = await _extract_port_from_spawned_companion(stdout)
        if not extracted_port:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, "
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        if port is not None and extracted_port != port:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, port is not correct (expected {port} got {extracted_port})"
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        return (process, extracted_port)


class CompanionSpawner:
    def __init__(self, companion_path: str, logger: logging.Logger) -> None:
        self.companion_path = companion_path
        self.logger = logger
        self.pid_saver = PidSaver(logger=self.logger)

    def _log_file_path(self, target_udid: str) -> str:
        os.makedirs(name=IDB_LOGS_PATH, exist_ok=True)
        return IDB_LOGS_PATH + "/" + target_udid

    def check_okay_to_spawn(self) -> None:
        if os.getuid() == 0:
            logging.warning(
                "idb should not be run as root. "
                "Listing available targets on this host and spawning "
                "companions will not work"
            )

    async def spawn_companion(self, target_udid: str) -> int:
        self.check_okay_to_spawn()
        (process, port) = await do_spawn_companion(
            path=self.companion_path,
            udid=target_udid,
            log_file_path=self._log_file_path(target_udid),
            device_set_path=None,
            port=None,
            cwd=None,
        )
        self.pid_saver.save_companion_pid(pid=process.pid)
        return port

    def _is_notifier_running(self) -> bool:
        pid = self.pid_saver.get_notifier_pid()
        # Taken from https://fburl.com/ibk820b6
        if pid <= 0:
            return False
        try:
            # no-op if process exists
            os.kill(pid, 0)
            return True
        except OSError as err:
            # EPERM clearly means there's a process to deny access to
            # otherwise proc doesn't exist
            return err.errno == errno.EPERM
        except Exception:
            return False

    async def spawn_notifier(self) -> None:
        if self._is_notifier_running():
            return

        self.check_okay_to_spawn()
        cmd = [self.companion_path, "--notify", IDB_LOCAL_TARGETS_FILE]
        with open(self._log_file_path("notifier"), "a") as log_file:
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=log_file
            )
            self.pid_saver.save_notifier_pid(pid=process.pid)
            await asyncio.ensure_future(
                self._read_notifier_output(stream=none_throws(process.stdout))
            )
            logging.debug(f"started notifier at process id {process.pid}")

    async def _read_notifier_output(self, stream: asyncio.StreamReader) -> None:
        while True:
            line = await stream.readline()
            if line is None:
                return
            update = json.loads(line.decode())
            if update["report_initial_state"]:
                return
