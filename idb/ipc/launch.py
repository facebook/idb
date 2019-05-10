#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import sys
from typing import Dict, List, Optional

from idb.grpc.idb_pb2 import LaunchRequest, LaunchResponse
from idb.grpc.stream import Stream, join_streams
from idb.grpc.types import CompanionClient


Start = LaunchRequest.Start
Stop = LaunchRequest.Stop


async def _drain_stream(stream: Stream[LaunchRequest, LaunchResponse]) -> None:
    async for message in stream:
        pipe = message.pipe
        if pipe:
            if message.interface == LaunchResponse.STDOUT:
                sys.stdout.buffer.write(pipe.data)
                sys.stdout.buffer.flush()
            elif message.interface == LaunchResponse.STDERR:
                sys.stderr.buffer.write(pipe.data)
                sys.stderr.buffer.flush()


async def _end_stream(
    stream: Stream[LaunchRequest, LaunchResponse], stop: asyncio.Event
) -> None:
    await stop.wait()
    await stream.send_message(LaunchRequest(stop=Stop()), end=True)


async def daemon(
    client: CompanionClient, stream: Stream[LaunchRequest, LaunchResponse]
) -> None:
    async with client.stub.launch.open() as out_stream:
        await join_streams(stream, out_stream)


async def client(
    client: CompanionClient,
    bundle_id: str,
    args: Optional[List[str]] = None,
    env: Optional[Dict[str, str]] = None,
    foreground_if_running: bool = False,
    stop: Optional[asyncio.Event] = None,
) -> None:
    async with client.stub.launch.open() as stream:
        request = LaunchRequest(
            start=Start(
                bundle_id=bundle_id,
                env=env,
                app_args=args,
                foreground_if_running=foreground_if_running,
                wait_for=True if stop else False,
            )
        )
        if stop:
            await stream.send_message(request)
            await asyncio.gather(_drain_stream(stream), _end_stream(stream, stop))
        else:
            await stream.send_message(request, end=True)
            await _drain_stream(stream)
