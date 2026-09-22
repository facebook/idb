#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import tempfile
from collections.abc import AsyncIterator
from pathlib import Path
from unittest.mock import MagicMock, patch

from grpclib.const import Status
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import InstrumentsRunRequest, InstrumentsRunResponse, Payload
from idb.utils.testing import TestCase


class _FakeInstrumentsStream:
    def __init__(self, stop: asyncio.Event, started: asyncio.Event) -> None:
        self.stop = stop
        self.started = started
        self.sent: list[InstrumentsRunRequest] = []
        self.half_closed = False
        self.end_calls = 0
        self.eof_reads = 0
        self.exited = False
        self.exit_exception: BaseException | None = None
        self.trailing_status = Status.OK
        self.checked_status: Status | None = None
        self.cancelled_read = asyncio.Event()
        self.started_when_running_returned: bool | None = None
        self.started_when_during_log_returned: bool | None = None
        self._before_half_close = [
            InstrumentsRunResponse(log_output=b"before\n"),
            InstrumentsRunResponse(state=InstrumentsRunResponse.RUNNING_INSTRUMENTS),
            InstrumentsRunResponse(log_output=b"during\n"),
        ]
        self._after_half_close: list[InstrumentsRunResponse | None] = [
            InstrumentsRunResponse(state=InstrumentsRunResponse.POST_PROCESSING),
            InstrumentsRunResponse(log_output=b"after\n"),
            InstrumentsRunResponse(payload=Payload(data=b"payload-1")),
            InstrumentsRunResponse(payload=Payload(data=b"payload-2")),
            None,
        ]

    async def __aenter__(self) -> _FakeInstrumentsStream:
        return self

    async def __aexit__(
        self,
        _exc_type: object,
        exception: BaseException | None,
        _traceback: object,
    ) -> None:
        self.exited = True
        self.exit_exception = exception
        self.checked_status = self.trailing_status

    async def send_message(self, message: InstrumentsRunRequest) -> None:
        if self.half_closed:
            raise AssertionError("request sent after client half-close")
        self.sent.append(message)

    async def end(self) -> None:
        self.end_calls += 1
        self.half_closed = True
        await asyncio.sleep(0)

    async def recv_message(self) -> InstrumentsRunResponse | None:
        if self.half_closed:
            response = self._after_half_close.pop(0)
            if response is None:
                self.eof_reads += 1
            return response

        if self._before_half_close:
            response = self._before_half_close.pop(0)
            if response.state == InstrumentsRunResponse.RUNNING_INSTRUMENTS:
                self.started_when_running_returned = self.started.is_set()
            if response.log_output == b"during\n":
                self.started_when_during_log_returned = self.started.is_set()
            return response

        self.stop.set()
        try:
            await asyncio.Event().wait()
        except asyncio.CancelledError:
            self.cancelled_read.set()
            raise
        raise AssertionError("unreachable")

    def __aiter__(self) -> _FakeInstrumentsStream:
        return self

    async def __anext__(self) -> InstrumentsRunResponse:
        response = await self.recv_message()
        if response is None:
            raise StopAsyncIteration
        return response


class InstrumentsTests(TestCase):
    async def test_start_running_stop_states_logs_and_payload(self) -> None:
        stop = asyncio.Event()
        started = asyncio.Event()
        stream = _FakeInstrumentsStream(stop=stop, started=started)
        logger = MagicMock()
        stub = MagicMock()
        stub.instruments_run.open.return_value = stream
        client = Client(stub=stub, companion=MagicMock(), logger=logger)
        payload_chunks: list[bytes] = []

        async def fake_drain_untar(
            generator: AsyncIterator[bytes],
            output_path: str,
            verbose: bool = False,
        ) -> None:
            payload_chunks.extend([chunk async for chunk in generator])
            Path(output_path, "result.trace").write_bytes(b"".join(payload_chunks))

        with tempfile.TemporaryDirectory() as output_dir:
            trace_basename = str(Path(output_dir, "capture"))
            trace_path = f"{trace_basename}.trace"
            with patch("idb.grpc.client.drain_untar", new=fake_drain_untar):
                result = await client.run_instruments(
                    stop=stop,
                    trace_basename=trace_basename,
                    template_name="Time Profiler",
                    app_bundle_id="com.example.app",
                    app_environment={"ENV": "value"},
                    app_arguments=["--app-argument"],
                    tool_arguments=["--tool-argument"],
                    started=started,
                    post_process_arguments=["--post-process"],
                )

            self.assertEqual(result, [trace_path])
            self.assertEqual(Path(trace_path).read_bytes(), b"payload-1payload-2")

        stub.instruments_run.open.assert_called_once_with()
        self.assertEqual(
            stream.sent,
            [
                InstrumentsRunRequest(
                    start=InstrumentsRunRequest.Start(
                        template_name="Time Profiler",
                        app_bundle_id="com.example.app",
                        environment={"ENV": "value"},
                        arguments=["--app-argument"],
                        tool_arguments=["--tool-argument"],
                    )
                ),
                InstrumentsRunRequest(
                    stop=InstrumentsRunRequest.Stop(
                        post_process_arguments=["--post-process"]
                    )
                ),
            ],
        )
        self.assertEqual(
            [request.WhichOneof("control") for request in stream.sent],
            ["start", "stop"],
        )
        self.assertIs(stream.started_when_running_returned, False)
        self.assertIs(stream.started_when_during_log_returned, True)
        self.assertTrue(started.is_set())
        self.assertEqual(stream.end_calls, 1)
        self.assertTrue(stream.half_closed)
        self.assertTrue(stream.cancelled_read.is_set())
        self.assertEqual(stream.eof_reads, 1)
        self.assertTrue(stream.exited)
        self.assertIsNone(stream.exit_exception)
        self.assertIs(stream.checked_status, Status.OK)
        self.assertEqual(payload_chunks, [b"payload-1", b"payload-2"])

        messages = [call.args[0] for call in logger.info.call_args_list]
        messages = [
            message
            for message in messages
            if not message.startswith("Writing instruments data from tar to ")
        ]
        self.assertEqual(
            messages,
            [
                "Starting instruments connection",
                "Sending instruments request",
                "Starting instruments",
                "before",
                "State changed to RUNNING_INSTRUMENTS",
                "Instruments has started, waiting for stop",
                "during\n",
                "Stopping instruments",
                "Instruments is post processing",
                "after",
                f"Trace written to {trace_path}",
            ],
        )
