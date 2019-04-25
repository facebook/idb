#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import logging
from typing import List, Optional


class BootManager:
    def __init__(self, companion_path: Optional[str]) -> None:
        self.companion_path = companion_path

    async def boot(self, udid: str) -> None:
        if self.companion_path:
            cmd: List[str] = [self.companion_path, "--boot", udid]
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            await process.communicate()
        else:
            logging.error(
                "Booting requires the daemon to be started with --notifier-path"
            )
