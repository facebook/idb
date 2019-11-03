#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import json
import logging
import socket
from contextlib import closing
from typing import Optional, Tuple

import aiofiles


DEFAULT_NETWORK_TIMEOUT: int = 3


def is_port_open(host: str, port: int) -> bool:
    with closing(socket.socket(socket.AF_INET6, socket.SOCK_STREAM)) as sock:
        sock.settimeout(DEFAULT_NETWORK_TIMEOUT)
        return sock.connect_ex((host, port)) == 0


async def gen_listening_ports_from_fd(
    process: asyncio.subprocess.Process,
    read_fd: int,
    timeout: Optional[int] = None,
    logger: Optional[logging.Logger] = None,
) -> Tuple[int, Optional[int]]:
    if logger is None:
        logger = logging.getLogger("reply-fd")
    wait = asyncio.ensure_future(process.wait())
    ports = asyncio.ensure_future(_read_from_fd(read_fd, logger))
    done, pending = await asyncio.wait(
        [wait, ports], return_when=asyncio.FIRST_COMPLETED
    )
    for fut in pending:
        fut.cancel()

    if ports not in done:
        raise Exception(
            f"Process exited with return code {process.returncode} before "
            f"responding with port"
        )
    return await ports


async def _read_from_fd(
    read_fd: int, logger: logging.Logger
) -> Tuple[int, Optional[int]]:
    async with aiofiles.open(read_fd, "r") as f:
        logger.info(f"Opened read_fd: {read_fd}")
        data = await f.readline()
        logger.info(f"Opened with data: {data} on read_fd: {read_fd}")
        return _get_ports(data)


def _get_ports(data: str) -> Tuple[int, Optional[int]]:
    all_ports = json.loads(data)
    return all_ports["grpc_port"]
