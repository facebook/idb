#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import json
import logging
import os
from asyncio import StreamReader
from asyncio.futures import Future
from typing import Dict, Optional

from idb.common.constants import IDB_LOGS_PATH
from idb.manager.companion import CompanionManager
from idb.common.types import Server, TargetDescription
from idb.utils.typing import none_throws


class CompanionTailerException(Exception):
    pass


class CompanionTailer(Server):
    def __init__(self, notifier_path: str, companion_manager: CompanionManager) -> None:
        self.notifier_path = notifier_path
        self._reading_forever_fut: Future[None]
        self.companion_manager = companion_manager
        self.process: Optional[asyncio.subprocess.Process] = None

    async def _read_stream(self, stream: StreamReader) -> None:
        while True:
            line = await stream.readline()
            if line:
                update = json.loads(line.decode())
                if "initial_state_ended" in update:
                    end_of_initial_state = update["initial_state_ended"]
                    if end_of_initial_state:
                        logging.debug(f"Initial state received from notifier")
                        break
                    else:
                        raise CompanionTailerException(
                            "Unexpected output from companion"
                        )
                self.companion_manager.update_target(
                    TargetDescription(
                        udid=update["udid"],
                        name=update["name"],
                        state=update["state"],
                        target_type=update["type"],
                        os_version=update["os_version"],
                        architecture=update["architecture"],
                        companion_info=None,
                        screen_dimensions=None,
                    )
                )
            else:
                break

    def _log_file_path(self) -> str:
        os.makedirs(name=IDB_LOGS_PATH, exist_ok=True)
        return IDB_LOGS_PATH + "/notifier"

    async def notifierProcess(self) -> asyncio.subprocess.Process:
        cmd = [self.notifier_path, "--notify", "1"]
        with open(self._log_file_path(), "a") as log_file:
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=log_file
            )
            await self._read_stream(none_throws(process.stdout))
            return process

    async def start(self) -> None:
        logging.debug(f"Started tailing notifier")
        if self.process:
            logging.warning(f"Trying to start companion tailer when already running")
            return
        self.process = await self.notifierProcess()
        if self.process:
            self._reading_forever_fut = asyncio.ensure_future(
                self._read_stream(stream=none_throws(self.process.stdout))
            )

    def close(self) -> None:
        logging.debug("Stopping companion tailer")
        self._reading_forever_fut.cancel()
        if self.process:
            self.process.terminate()

    async def wait_closed(self) -> None:
        pass

    @property
    def ports(self) -> Dict[str, int]:
        return {}
