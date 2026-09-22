#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path
from unittest.mock import call, patch

from idb.grpc.idb_pb2 import (
    DebuggerInfo as GrpcDebuggerInfo,
    LaunchRequest,
    LaunchResponse,
    ProcessOutput,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class LaunchStreamTests(TestCase):
    async def test_start_output_debugger_stop_and_half_close(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for waits_for_stop in (False, True):
                with self.subTest(waits_for_stop=waits_for_stop):
                    stream = ScriptedStream(
                        LaunchResponse(
                            output=ProcessOutput(
                                interface=ProcessOutput.STDOUT,
                                data=b"stdout",
                            )
                        ),
                        LaunchResponse(
                            output=ProcessOutput(
                                interface=ProcessOutput.STDERR,
                                data=b"stderr",
                            )
                        ),
                        LaunchResponse(debugger=GrpcDebuggerInfo(pid=42)),
                    )
                    client, open_rpc = make_client("launch", stream)
                    stop = asyncio.Event() if waits_for_stop else None
                    if stop is not None:
                        stop.set()
                    pid_file = (
                        str(Path(directory) / "debugger.json")
                        if waits_for_stop
                        else None
                    )

                    with patch("idb.grpc.launch.sys") as stdio:
                        await client.launch(
                            bundle_id="com.example.app",
                            args=["first", "second"],
                            env={"IDB_TOKEN": "value"},
                            foreground_if_running=True,
                            wait_for_debugger=True,
                            stop=stop,
                            pid_file=pid_file,
                            enable_repl=True,
                        )

                    start = LaunchRequest(
                        start=LaunchRequest.Start(
                            bundle_id="com.example.app",
                            env={"IDB_TOKEN": "value"},
                            app_args=["first", "second"],
                            foreground_if_running=True,
                            wait_for_debugger=True,
                            wait_for=waits_for_stop,
                            enable_repl=True,
                        )
                    )
                    stop_request = LaunchRequest(stop=LaunchRequest.Stop())
                    expected_sent = [(start, False)]
                    responses = [
                        (
                            "recv",
                            LaunchResponse(
                                output=ProcessOutput(
                                    interface=ProcessOutput.STDOUT,
                                    data=b"stdout",
                                )
                            ),
                        ),
                        (
                            "recv",
                            LaunchResponse(
                                output=ProcessOutput(
                                    interface=ProcessOutput.STDERR,
                                    data=b"stderr",
                                )
                            ),
                        ),
                        (
                            "recv",
                            LaunchResponse(debugger=GrpcDebuggerInfo(pid=42)),
                        ),
                        ("recv", None),
                    ]
                    if waits_for_stop:
                        expected_sent.append((stop_request, False))
                        expected_transcript = [
                            ("send", start),
                            *responses,
                            ("send", stop_request),
                            ("end", None),
                        ]
                    else:
                        expected_transcript = [
                            ("send", start),
                            ("end", None),
                            *responses,
                        ]
                    self.assertEqual(stream.sent, expected_sent)
                    self.assertEqual(stream.transcript, expected_transcript)
                    self.assertEqual(
                        stdio.mock_calls[:4],
                        [
                            call.stdout.buffer.write(b"stdout"),
                            call.stdout.buffer.flush(),
                            call.stderr.buffer.write(b"stderr"),
                            call.stderr.buffer.flush(),
                        ],
                    )
                    if pid_file is None:
                        self.assertEqual(
                            stdio.mock_calls[4:],
                            [
                                call.stdout.buffer.write(b'{"pid": 42}\n'),
                                call.stdout.buffer.flush(),
                            ],
                        )
                    else:
                        self.assertEqual(stdio.mock_calls[4:], [])
                        self.assertEqual(Path(pid_file).read_bytes(), b'{"pid": 42}')
                    open_rpc.assert_called_once_with()
                    self.assertTrue(stream.entered)
                    self.assertTrue(stream.exited)
