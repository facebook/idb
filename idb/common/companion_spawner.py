#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import json
import logging
import os
from asyncio import StreamReader
from typing import List

from idb.client.pid_saver import PidSaver
from idb.common.constants import IDB_LOCAL_TARGETS_FILE, IDB_LOGS_PATH
from idb.utils.typing import none_throws


class CompanionSpawnerException(Exception):
    pass


class CompanionSpawner:
    def __init__(self, companion_path: str, logger: logging.Logger) -> None:
        self.companion_path = companion_path
        self.logger = logger
        self.pid_saver = PidSaver(logger=self.logger)

    async def _read_stream(self, stream: StreamReader) -> int:
        port = 0
        while True:
            line = await stream.readline()
            logging.debug(f"read line from companion : {line}")
            if line:
                update = json.loads(line.decode())
                if update:
                    logging.debug(f"got update from companion {update}")
                    port = update["grpc_port"]
                    break
            else:
                break
        return port

    def _log_file_path(self, target_udid: str) -> str:
        os.makedirs(name=IDB_LOGS_PATH, exist_ok=True)
        return IDB_LOGS_PATH + "/" + target_udid

    async def spawn_companion(self, target_udid: str) -> int:
        if not self.companion_path:
            raise CompanionSpawnerException(
                f"couldn't instantiate a companion for {target_udid} because\
                 the companion_path is not available"
            )
        cmd: List[str] = [
            self.companion_path,
            "--udid",
            target_udid,
            "--grpc-port",
            "0",
        ]

        with open(self._log_file_path(target_udid), "a") as log_file:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.PIPE,
                stderr=log_file,
            )
            self.pid_saver.save_companion_pid(pid=process.pid)
            logging.debug(f"started companion at process id {process.pid}")
            if process.stdout:
                # pyre-fixme[6]: Expected `StreamReader` for 1st param but got
                #  `Optional[StreamReader]`.
                port = await self._read_stream(process.stdout)
                if not port:
                    raise CompanionSpawnerException("failed to spawn companion")
                return port
            raise CompanionSpawnerException("process has no stdout")

    def _is_notifier_running(self) -> bool:
        return self.pid_saver.get_notifier_pid() > 0

    async def spawn_notifier(self) -> None:
        if not self._is_notifier_running():
            if not self.companion_path:
                raise CompanionSpawnerException(
                    f"couldn't instantiate a notifier because\
                     the companion_path is not available"
                )
            cmd: List[str] = [self.companion_path, "--notify", IDB_LOCAL_TARGETS_FILE]

            with open(self._log_file_path("notifier"), "a") as log_file:
                process = await asyncio.create_subprocess_exec(
                    *cmd, stdout=asyncio.subprocess.PIPE, stderr=log_file
                )
                self.pid_saver.save_notifier_pid(pid=process.pid)
                await asyncio.ensure_future(
                    self._read_notifier_output(stream=none_throws(process.stdout))
                )
                logging.debug(f"started notifier at process id {process.pid}")

    async def _read_notifier_output(self, stream: StreamReader) -> None:
        while True:
            line = await stream.readline()
            if line:
                update = json.loads(line.decode())
                if update["report_initial_state"]:
                    return
            else:
                return
