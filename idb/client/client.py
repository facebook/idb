#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import inspect
import logging
from typing import Any, Callable, Optional, Set

from idb.client.daemon_pid_saver import kill_saved_pids
from idb.common.types import IdbClientBase


BASE_MEMBERS: Set[str] = {
    name
    for (name, value) in inspect.getmembers(IdbClientBase)
    if not name.startswith("__")
}


class IdbClient(IdbClientBase):
    def __init__(
        self,
        resolve: Callable[[str], IdbClientBase],
        logger: Optional[logging.Logger] = None,
    ) -> None:
        self.logger: logging.Logger = logger or logging.getLogger("idb_client")
        self._resolve = resolve

    def __getattribute__(self, key: str) -> Any:  # pyre-ignore
        if key not in BASE_MEMBERS:
            return super().key
        logger = super().__getattribute__("logger")
        logger.debug(f"Resolving client for {key}")
        client = super().__getattribute__("_resolve")(key)
        logger.debug(f"Resolved client for {key} to {client}")
        return getattr(client, key)

    @classmethod
    async def kill(cls) -> None:
        await kill_saved_pids()
