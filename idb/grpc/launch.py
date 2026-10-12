#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import sys

from idb.common.format import json_format_debugger_info
from idb.common.types import DebuggerInfo
from idb.grpc.idb_pb2 import LaunchRequest, LaunchResponse, ProcessOutput
from idb.grpc.stream import Stream


async def wait_for_launch_stream(
    stream: Stream[LaunchRequest, LaunchResponse],
    stop: asyncio.Event,
    pid_file: str | None,
) -> None:
    drain = asyncio.create_task(drain_launch_stream(stream, pid_file))
    stopped = asyncio.create_task(stop.wait())
    try:
        done, _ = await asyncio.wait(
            (drain, stopped), return_when=asyncio.FIRST_COMPLETED
        )
        if drain in done:
            await drain
        else:
            await stream.send_message(LaunchRequest(stop=LaunchRequest.Stop()))
        # grpclib raises if a call exits before its requests are ended, even after
        # the response ends
        await stream.end()
        # The companion still forwards the app's final output after Stop, until it
        # ends the response
        await drain
    finally:
        drain.cancel()
        stopped.cancel()
        await asyncio.gather(drain, stopped, return_exceptions=True)


async def drain_launch_stream(
    stream: Stream[LaunchRequest, LaunchResponse], pid_file: str | None
) -> None:
    async for message in stream:
        output = message.output
        data = output.data
        if len(data):
            interface = output.interface
            if interface == ProcessOutput.STDOUT:
                sys.stdout.buffer.write(data)
                sys.stdout.buffer.flush()
            elif interface == ProcessOutput.STDERR:
                sys.stderr.buffer.write(data)
                sys.stderr.buffer.flush()
        debugger_info = message.debugger
        debugger_pid = debugger_info.pid
        if debugger_pid is not None and debugger_pid != 0:
            info = DebuggerInfo(pid=debugger_info.pid)
            if pid_file is None:
                sys.stdout.buffer.write(
                    json_format_debugger_info(info).encode() + b"\n"
                )
                sys.stdout.buffer.flush()
            else:
                with open(pid_file, "wb") as f:
                    f.write(json_format_debugger_info(info).encode())
                    f.flush()
