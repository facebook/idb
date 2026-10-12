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

from grpclib.exceptions import ProtocolError
from idb.common.types import IdbException
from idb.grpc.idb_pb2 import (
    DebuggerInfo as GrpcDebuggerInfo,
    LaunchRequest,
    LaunchResponse,
    ProcessOutput,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class LaunchStreamTests(TestCase):
    async def test_response_eof_completes_without_stop(self) -> None:
        last_output = LaunchResponse(
            output=ProcessOutput(interface=ProcessOutput.STDOUT, data=b"last output")
        )
        stream = ScriptedStream(last_output)
        client, _ = make_client("launch", stream)
        stop = asyncio.Event()
        tasks = asyncio.all_tasks()

        with patch("idb.grpc.launch.sys") as stdio:
            await asyncio.wait_for(
                client.launch(bundle_id="com.example.app", stop=stop), timeout=1
            )

        self.assertFalse(stop.is_set())
        self.assertEqual(
            stream.transcript,
            [
                (
                    "send",
                    LaunchRequest(
                        start=LaunchRequest.Start(
                            bundle_id="com.example.app", wait_for=True
                        )
                    ),
                ),
                ("recv", last_output),
                ("recv", None),
                # grpclib raises if a call exits before its requests are ended
                ("end", None),
            ],
        )
        self.assertEqual(
            stdio.mock_calls,
            [call.stdout.buffer.write(b"last output"), call.stdout.buffer.flush()],
        )
        self.assertEqual(asyncio.all_tasks(), tasks)
        self.assertTrue(stream.exited)

    async def test_stop_preserves_final_output(self) -> None:
        final_response = LaunchResponse(
            output=ProcessOutput(interface=ProcessOutput.STDOUT, data=b"final output")
        )
        stream = _StopDrivenLaunchStream(final_response)
        client, _ = make_client("launch", stream)
        stop = asyncio.Event()

        with patch("idb.grpc.launch.sys") as stdio:
            async with asyncio.timeout(1):
                launch = asyncio.create_task(
                    client.launch(bundle_id="com.example.app", stop=stop)
                )
                try:
                    await stream.read_started.wait()
                    self.assertFalse(launch.done())
                    self.assertFalse(stream.requests_ended.is_set())
                    stop.set()
                    await launch
                finally:
                    launch.cancel()
                    await asyncio.gather(launch, return_exceptions=True)

        self.assertEqual(
            stream.sent[1:], [(LaunchRequest(stop=LaunchRequest.Stop()), False)]
        )
        self.assertEqual(
            stream.transcript[1:],
            [
                ("send", LaunchRequest(stop=LaunchRequest.Stop())),
                ("end", None),
                ("recv", final_response),
                ("recv", None),
            ],
        )
        self.assertEqual(
            stdio.mock_calls,
            [call.stdout.buffer.write(b"final output"), call.stdout.buffer.flush()],
        )
        self.assertEqual(stream.read_cancellations, 0)
        self.assertTrue(stream.exited)

    async def test_response_error_settles_pending_stop(self) -> None:
        stream = ScriptedStream[LaunchResponse]()
        client, _ = make_client("launch", stream)
        stop = asyncio.Event()
        failure = ProtocolError("launch response failed")
        tasks = asyncio.all_tasks()

        with patch.object(stream, "recv_message", side_effect=failure):
            with self.assertRaises(IdbException) as raised:
                await client.launch(bundle_id="com.example.app", stop=stop)

        self.assertIs(raised.exception.__cause__, failure)
        self.assertFalse(stop.is_set())
        self.assertEqual(asyncio.all_tasks(), tasks)
        self.assertTrue(stream.exited)

    async def test_stop_error_settles_pending_read(self) -> None:
        stream = _StopDrivenLaunchStream()
        client, _ = make_client("launch", stream)
        stop = asyncio.Event()
        stop.set()
        failure = ProtocolError("launch Stop failed")
        tasks = asyncio.all_tasks()
        send_message = stream.send_message

        async def send_request(message: LaunchRequest) -> None:
            if message.HasField("stop"):
                raise failure
            await send_message(message)

        with patch.object(stream, "send_message", side_effect=send_request):
            with self.assertRaises(IdbException) as raised:
                await client.launch(bundle_id="com.example.app", stop=stop)

        self.assertIs(raised.exception.__cause__, failure)
        self.assertEqual(stream.read_cancellations, 1)
        self.assertEqual(asyncio.all_tasks(), tasks)
        self.assertTrue(stream.exited)

    async def test_parent_cancellation_settles_read_and_stop(self) -> None:
        stream = _StopDrivenLaunchStream()
        client, _ = make_client("launch", stream)
        stop = asyncio.Event()
        tasks = asyncio.all_tasks()

        async with asyncio.timeout(1):
            launch = asyncio.create_task(
                client.launch(bundle_id="com.example.app", stop=stop)
            )
            try:
                await stream.read_started.wait()
                launch.cancel()
                with self.assertRaises(asyncio.CancelledError):
                    await launch
            finally:
                launch.cancel()
                await asyncio.gather(launch, return_exceptions=True)

        self.assertFalse(stop.is_set())
        self.assertEqual(stream.read_cancellations, 1)
        self.assertEqual(asyncio.all_tasks(), tasks)
        self.assertTrue(stream.exited)

    async def test_start_output_debugger_stop_and_half_close(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for waits_for_stop in (False, True):
                with self.subTest(waits_for_stop=waits_for_stop):
                    stream_type = (
                        _StopDrivenLaunchStream if waits_for_stop else ScriptedStream
                    )
                    stream = stream_type(
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
                            ("send", stop_request),
                            ("end", None),
                            *responses,
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


class _StopDrivenLaunchStream(ScriptedStream[LaunchResponse]):
    """Withholds responses until the client ends its requests, which follows Stop."""

    def __init__(self, *responses: LaunchResponse) -> None:
        super().__init__(*responses)
        self.read_started = asyncio.Event()
        self.requests_ended = asyncio.Event()

    async def recv_message(self) -> LaunchResponse | None:
        self.read_started.set()
        try:
            await self.requests_ended.wait()
        except asyncio.CancelledError:
            self.read_cancellations += 1
            raise
        return await super().recv_message()

    async def end(self) -> None:
        await super().end()
        self.requests_ended.set()
