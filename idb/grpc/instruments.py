#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
from logging import Logger
from typing import AsyncIterator, Optional

from idb.common.types import InstrumentsTimings
from idb.grpc.idb_pb2 import InstrumentsRunRequest, InstrumentsRunResponse
from idb.grpc.stream import Stream
from idb.utils.typing import none_throws


async def instruments_generate_bytes(
    stream: Stream[InstrumentsRunRequest, InstrumentsRunResponse], logger: Logger
) -> AsyncIterator[bytes]:
    async for response in stream:
        log_output = response.log_output
        if len(log_output):
            logger.info(log_output.decode().strip())
            continue
        if response.state == InstrumentsRunResponse.POST_PROCESSING:
            logger.info("Instruments is post processing")
            continue
        data = response.payload.data
        if len(data):
            yield data


async def instruments_drain_until_running(
    stream: Stream[InstrumentsRunRequest, InstrumentsRunResponse], logger: Logger
) -> None:
    while True:
        response = none_throws(await stream.recv_message())
        log_output = response.log_output
        if len(log_output):
            logger.info(log_output.decode().strip())
            continue
        state = response.state
        if state == InstrumentsRunResponse.RUNNING_INSTRUMENTS:
            logger.info("State changed to RUNNING_INSTRUMENTS")
            return


async def instruments_drain_until_stop(
    stream: Stream[InstrumentsRunRequest, InstrumentsRunResponse],
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
        output = response.log_output
        if len(output):
            logger.info(output.decode())


def translate_instruments_timings(
    timings: Optional[InstrumentsTimings]
) -> Optional[InstrumentsRunRequest.InstrumentsTimings]:
    return (
        InstrumentsRunRequest.InstrumentsTimings(
            terminate_timeout=timings.terminate_timeout,
            launch_retry_timeout=timings.launch_retry_timeout,
            launch_error_timeout=timings.launch_error_timeout,
            operation_duration=timings.operation_duration,
        )
        if timings
        else None
    )
