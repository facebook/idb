#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


import asyncio
import os
from logging import Logger
from typing import AsyncIterator, Dict, List, Optional

from idb.grpc.types import CompanionClient
from idb.grpc.stream import Stream
from idb.common.tar import drain_untar
from idb.grpc.idb_pb2 import InstrumentsRunRequest, InstrumentsRunResponse
from idb.utils.typing import none_throws


Start = InstrumentsRunRequest.Start
Stop = InstrumentsRunRequest.Stop


async def _generate_bytes(
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


async def _drain_until_running(
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


async def _drain_until_stop(
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


async def run_instruments(
    client: CompanionClient,
    stop: asyncio.Event,
    template: str,
    app_bundle_id: str,
    trace_path: str,
    post_process_arguments: Optional[List[str]] = None,
    env: Optional[Dict[str, str]] = None,
    app_args: Optional[List[str]] = None,
    started: Optional[asyncio.Event] = None,
) -> str:
    trace_path = os.path.realpath(trace_path)
    client.logger.info(f"Starting instruments connection, writing to {trace_path}")
    async with client.stub.instruments_run.open() as stream:
        client.logger.info("Sending instruments request")
        await stream.send_message(
            InstrumentsRunRequest(
                start=Start(
                    file_path=None,
                    template_name=template,
                    app_bundle_id=app_bundle_id,
                    environment=env,
                    arguments=app_args,
                )
            )
        )
        client.logger.info("Starting instruments")
        await _drain_until_running(stream=stream, logger=client.logger)
        if started:
            started.set()
        client.logger.info("Instruments has started, waiting for stop")
        await _drain_until_stop(
            stream=stream, stop=asyncio.ensure_future(stop.wait()), logger=client.logger
        )
        client.logger.info("Stopping instruments")
        await stream.send_message(
            InstrumentsRunRequest(
                stop=Stop(post_process_arguments=post_process_arguments)
            ),
            end=True,
        )
        client.logger.info(f"Writing instruments from tar to {trace_path}")
        await drain_untar(
            _generate_bytes(stream=stream, logger=client.logger), output_path=trace_path
        )
        client.logger.info(f"Instruments trace written to {trace_path}")
        return trace_path


CLIENT_PROPERTIES = [run_instruments]  # pyre-ignore
