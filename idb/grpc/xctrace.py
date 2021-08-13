#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import re
from logging import Logger
from typing import AsyncIterator, Optional

from idb.grpc.idb_pb2 import (
    XctraceRecordRequest,
    XctraceRecordResponse,
)
from idb.grpc.stream import Stream
from idb.utils.typing import none_throws


async def xctrace_generate_bytes(
    stream: Stream[XctraceRecordRequest, XctraceRecordResponse], logger: Logger
) -> AsyncIterator[bytes]:
    async for response in stream:
        log = response.log
        if len(log):
            logger.info(log.decode().strip())
            continue
        if response.state == XctraceRecordResponse.PROCESSING:
            logger.info("Processing the .trace file")
            continue
        data = response.payload.data
        if len(data):
            yield data


async def xctrace_drain_until_running(
    stream: Stream[XctraceRecordRequest, XctraceRecordResponse], logger: Logger
) -> None:
    async for response in stream:
        log = response.log
        if len(log):
            logger.info(log.decode().strip())
            continue
        state = response.state
        if state == XctraceRecordResponse.RUNNING:
            logger.info("Xctrace record is running now")
            return


async def xctrace_drain_until_stop(
    stream: Stream[XctraceRecordRequest, XctraceRecordResponse],
    stop: asyncio.Future,
    logger: Logger,
) -> None:
    while True:
        read = asyncio.ensure_future(stream.recv_message())
        done, pending = await asyncio.wait(
            [stop, read], return_when=asyncio.FIRST_COMPLETED
        )
        if stop in done:
            return
        response = none_throws(read.result())
        output = response.log
        if len(output):
            logger.info(output.decode())


def formatted_time_to_seconds(formatted_time: Optional[str]) -> Optional[float]:
    if not formatted_time:
        return None
    pattern = r"^([1-9]\d*)(ms|s|m|h)$"
    match = re.search(pattern, formatted_time)
    if not match:
        raise Exception(
            f"Invalid time limit format: {formatted_time}. time[ms|s|m|h] expected"
        )
    time = float(match.group(1))
    if match.group(2) == "ms":
        return time / 1000.0
    elif match.group(2) == "m":
        return time * 60.0
    elif match.group(2) == "h":
        return time * 60.0 * 60.0
    else:
        return time
