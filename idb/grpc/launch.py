#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import sys
from typing import Optional

from idb.common.format import json_format_debugger_info
from idb.common.types import DebuggerInfo
from idb.grpc.idb_pb2 import LaunchRequest, LaunchResponse, ProcessOutput
from idb.grpc.stream import Stream


async def drain_launch_stream(
    stream: Stream[LaunchRequest, LaunchResponse], pid_file: Optional[str]
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
                sys.stdout.buffer.write(json_format_debugger_info(info).encode())
                sys.stdout.buffer.flush()
            else:
                with open(pid_file, "wb") as f:
                    f.write(json_format_debugger_info(info).encode())
                    f.flush()


async def end_launch_stream(
    stream: Stream[LaunchRequest, LaunchResponse], stop: asyncio.Event
) -> None:
    await stop.wait()
    await stream.send_message(LaunchRequest(stop=LaunchRequest.Stop()))
    await stream.end()
