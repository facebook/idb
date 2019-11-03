#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import sys

from idb.grpc.idb_pb2 import LaunchRequest, LaunchResponse
from idb.grpc.stream import Stream


async def drain_launch_stream(stream: Stream[LaunchRequest, LaunchResponse]) -> None:
    async for message in stream:
        pipe = message.pipe
        if pipe:
            if message.interface == LaunchResponse.STDOUT:
                sys.stdout.buffer.write(pipe.data)
                sys.stdout.buffer.flush()
            elif message.interface == LaunchResponse.STDERR:
                sys.stderr.buffer.write(pipe.data)
                sys.stderr.buffer.flush()


async def end_launch_stream(
    stream: Stream[LaunchRequest, LaunchResponse], stop: asyncio.Event
) -> None:
    await stop.wait()
    await stream.send_message(LaunchRequest(stop=LaunchRequest.Stop()))
    await stream.end()
