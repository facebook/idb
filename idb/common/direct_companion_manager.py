#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from pathlib import Path
from typing import IO, AsyncGenerator, List, Optional

from idb.common.constants import IDB_STATE_FILE_PATH
from idb.common.format import json_data_companions, json_to_companion_info
from idb.common.types import CompanionInfo, ConnectionDestination, IdbException


# this is the new companion manager for direct_client mode


@asynccontextmanager
async def exclusive_rw_open(filename: str) -> AsyncGenerator[IO[str], None]:
    timeout = 3
    retry_time = 0.05
    lockfile = filename + ".lock"
    deadline = datetime.now() + timedelta(seconds=timeout)
    while True:
        try:
            fd = os.open(lockfile, os.O_CREAT | os.O_EXCL)
            break
        except FileExistsError:
            if datetime.now() >= deadline:
                raise
            await asyncio.sleep(retry_time)
    try:
        # r+ will not create the file like w will, we have to create it first
        Path(filename).touch(exist_ok=True)
        with open(filename, "r+") as f:
            yield f
    finally:
        try:
            os.close(fd)  # pyre-ignore
        finally:
            os.unlink(lockfile)


class DirectCompanionManager:
    def __init__(
        self, logger: logging.Logger, state_file_path: str = IDB_STATE_FILE_PATH
    ) -> None:
        self.state_file_path = state_file_path
        self.logger = logger
        self.logger.info(f"idb state file stored at {self.state_file_path}")

    @asynccontextmanager
    async def _use_stored_companions(self) -> AsyncGenerator[List[CompanionInfo], None]:
        async with exclusive_rw_open(self.state_file_path) as f:
            try:
                companion_info_in = json_to_companion_info(json.load(f))
            except json.JSONDecodeError:
                companion_info_in = []
            companion_info_out = list(companion_info_in)
            yield companion_info_out
            if companion_info_in == companion_info_out:
                return
            f.seek(0)
            json.dump(json_data_companions(companion_info_out), f)
            f.truncate()

    async def get_companions(self) -> List[CompanionInfo]:
        async with self._use_stored_companions() as companions:
            return companions

    async def add_companion(self, companion: CompanionInfo) -> None:
        async with self._use_stored_companions() as companions:
            if companion in companions:
                self.logger.info(f"companion {companion} already added")
                return
            companions.append(companion)
            self.logger.info(f"added direct companion {companion}")

    async def clear(self) -> None:
        async with self._use_stored_companions() as companions:
            companions.clear()

    async def get_companion_info(self, target_udid: Optional[str]) -> CompanionInfo:
        async with self._use_stored_companions() as companions:
            matching = [
                companion for companion in companions if companion.udid == target_udid
            ]
            if target_udid is not None:
                if len(matching) > 0:
                    return companions[0]
                else:
                    raise IdbException(
                        f"Couldn't find companion for target with udid {target_udid}"
                    )
            elif len(matching) >= 1:
                companion = companions[0]
                self.logger.info(f"using default companion with udid {companion.udid}")
                return companion
            else:
                raise IdbException(
                    "No UDID provided and couldn't find a default companion"
                )

    async def remove_companion(self, destination: ConnectionDestination) -> None:
        async with self._use_stored_companions() as companions:
            if isinstance(destination, str):
                to_remove = [
                    companion
                    for companion in companions
                    if companion.udid == destination
                ]
            else:
                to_remove = [
                    companion
                    for companion in companions
                    if companion.host == destination.host
                    and companion.port == destination.port
                ]
            for companion in to_remove:
                companions.remove(companion)
