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
from typing import IO, AsyncGenerator, List, Optional

from idb.common.constants import IDB_STATE_FILE_PATH
from idb.common.format import json_data_companions, json_to_companion_info
from idb.common.types import CompanionInfo, ConnectionDestination, IdbException


# this is the new companion manager for direct_client mode


@asynccontextmanager
async def exclusive_open(
    filename: str, *args, **kwargs  # pyre-ignore
) -> AsyncGenerator[IO[str], None]:
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
        with open(filename, *args, **kwargs) as f:
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
        self.companions: List[CompanionInfo] = []
        self.state_file_path = state_file_path
        self.logger = logger
        self.logger.info(f"idb state file stored at {self.state_file_path}")

    async def add_companion(self, companion: CompanionInfo) -> None:
        await self.get_companions()
        if companion in self.companions:
            self.logger.info(f"companion {companion} already added")
        else:
            self.companions.append(companion)
            self.logger.info(f"added direct companion {companion}")
        await self._save()

    async def get_companions(self) -> List[CompanionInfo]:
        self.companions = await self._load()
        return self.companions

    async def _save(self) -> None:
        async with exclusive_open(self.state_file_path, "w") as f:
            json.dump(json_data_companions(self.companions), f)

    async def _load(self) -> List[CompanionInfo]:
        if not os.path.exists(self.state_file_path):
            return []
        async with exclusive_open(self.state_file_path, "r") as f:
            return json_to_companion_info(json.load(f))

    async def clear(self) -> None:
        self.companions = []
        await self._save()

    async def get_companion_info(self, target_udid: Optional[str]) -> CompanionInfo:
        await self.get_companions()
        if target_udid:
            companions = [
                companion
                for companion in self.companions
                if companion.udid == target_udid
            ]
            if len(companions) > 0:
                return companions[0]
            else:
                raise IdbException(
                    f"Couldn't find companion for target with udid {target_udid}"
                )
        elif len(self.companions) >= 1:
            companion = self.companions[0]
            self.logger.info(f"using default companion with udid {companion.udid}")
            return companion
        else:
            raise IdbException("No UDID provided and couldn't find a default companion")

    async def remove_companion(self, destination: ConnectionDestination) -> None:
        await self.get_companions()
        companions = []
        if isinstance(destination, str):
            companions = [
                companion
                for companion in self.companions
                if companion.udid == destination
            ]
        else:
            companions = [
                companion
                for companion in self.companions
                if companion.host == destination.host
                and companion.port == destination.port
            ]
        for companion in companions:
            self.companions.remove(companion)
        await self._save()
