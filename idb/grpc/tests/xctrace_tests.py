#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import os
import tempfile
from collections.abc import AsyncIterator
from unittest.mock import MagicMock, patch

from grpclib.const import Status
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import Payload, XctraceRecordRequest, XctraceRecordResponse
from idb.grpc.stream import Stream
from idb.grpc.xctrace import xctrace_drain_until_running
from idb.utils.testing import TestCase


class _FakeXctraceStream(Stream[XctraceRecordRequest, XctraceRecordResponse]):
    def __init__(
        self,
        *,
        initial: tuple[XctraceRecordResponse | None, ...],
        after_half_close: tuple[XctraceRecordResponse, ...] = (),
    ) -> None:
        self.actions: list[tuple[str, XctraceRecordRequest | None]] = []
        self.eof_seen = False
        self.trailing_status = Status.OK
        self.checked_status: Status | None = None
        self.exit_exception: BaseException | None = None
        self._after_half_close = after_half_close
        self._responses: asyncio.Queue[XctraceRecordResponse | None] = asyncio.Queue()
        for response in initial:
            self._responses.put_nowait(response)

    async def __aenter__(self) -> _FakeXctraceStream:
        return self

    async def __aexit__(
        self,
        _exc_type: object,
        exception: BaseException | None,
        _traceback: object,
    ) -> None:
        self.exit_exception = exception
        self.checked_status = self.trailing_status

    def __aiter__(self) -> AsyncIterator[XctraceRecordResponse]:
        return self

    async def __anext__(self) -> XctraceRecordResponse:
        response = await self.recv_message()
        if response is None:
            raise StopAsyncIteration
        return response

    async def recv_message(self) -> XctraceRecordResponse | None:
        response = await self._responses.get()
        if response is None:
            self.eof_seen = True
        return response

    async def send_message(self, message: XctraceRecordRequest) -> None:
        self.actions.append(("send", message))

    async def end(self) -> None:
        self.actions.append(("end", None))
        await asyncio.sleep(0)
        for response in self._after_half_close:
            self._responses.put_nowait(response)
        self._responses.put_nowait(None)

    async def cancel(self) -> None:
        self.actions.append(("cancel", None))

    def push(self, response: XctraceRecordResponse) -> None:
        self._responses.put_nowait(response)


class XctraceTests(TestCase):
    async def test_start_running_stop_states_logs_and_payload(self) -> None:
        stream = _FakeXctraceStream(
            initial=(
                XctraceRecordResponse(log=b"before\n"),
                XctraceRecordResponse(state=XctraceRecordResponse.RUNNING),
            ),
            after_half_close=(
                XctraceRecordResponse(log=b"after\n"),
                XctraceRecordResponse(state=XctraceRecordResponse.PROCESSING),
                XctraceRecordResponse(payload=Payload(data=b"trace payload")),
            ),
        )
        logger = MagicMock()
        during_logged = asyncio.Event()

        def observe_log(message: object) -> None:
            if message == "during\n":
                during_logged.set()

        logger.info.side_effect = observe_log
        client = Client.__new__(Client)
        client.stub = MagicMock()
        client.stub.xctrace_record.open.return_value = stream
        client.logger = logger
        started = asyncio.Event()
        stop = asyncio.Event()
        received_payload: list[bytes] = []

        expected_start = XctraceRecordRequest(
            start=XctraceRecordRequest.Start(
                template_name="Time Profiler",
                time_limit=3.5,
                package="com.meta.template",
                target=XctraceRecordRequest.Target(all_processes=True),
            )
        )
        expected_stop = XctraceRecordRequest(
            stop=XctraceRecordRequest.Stop(
                timeout=4.5,
                args=["--post-process"],
            )
        )

        async def fake_drain_untar(
            generator: AsyncIterator[bytes],
            output_path: str,
        ) -> None:
            received_payload.extend([chunk async for chunk in generator])
            os.mkdir(os.path.join(output_path, "instrument_data"))

        with tempfile.TemporaryDirectory() as tmp_dir:
            output = os.path.join(tmp_dir, "capture")
            with patch("idb.grpc.client.drain_untar", new=fake_drain_untar):
                task = asyncio.create_task(
                    client.xctrace_record(
                        stop=stop,
                        output=output,
                        template_name="Time Profiler",
                        all_processes=True,
                        time_limit=3.5,
                        package="com.meta.template",
                        post_args=["--post-process"],
                        stop_timeout=4.5,
                        started=started,
                    )
                )
                try:
                    await asyncio.wait_for(started.wait(), timeout=5)
                    self.assertTrue(started.is_set())
                    self.assertFalse(task.done())
                    self.assertEqual(stream.actions, [("send", expected_start)])
                    stream.push(XctraceRecordResponse(log=b"during\n"))
                    await asyncio.wait_for(during_logged.wait(), timeout=5)
                    stop.set()
                    result = await asyncio.wait_for(task, timeout=5)
                finally:
                    if not task.done():
                        task.cancel()
                        try:
                            await task
                        except asyncio.CancelledError:
                            pass

            self.assertEqual(
                stream.actions,
                [
                    ("send", expected_start),
                    ("send", expected_stop),
                    ("end", None),
                ],
            )
            self.assertEqual(result, [f"{output}.trace"])
            self.assertEqual(received_payload, [b"trace payload"])
            self.assertTrue(os.path.isdir(os.path.join(result[0], "instrument_data")))

        relevant_logs = {
            "before",
            "Xctrace record is running now",
            "during\n",
            "after",
            "Processing the .trace file",
        }
        self.assertEqual(
            [
                call.args[0]
                for call in logger.info.call_args_list
                if call.args[0] in relevant_logs
            ],
            [
                "before",
                "Xctrace record is running now",
                "during\n",
                "after",
                "Processing the .trace file",
            ],
        )
        self.assertTrue(stream.eof_seen)
        self.assertIsNone(stream.exit_exception)
        self.assertIs(stream.checked_status, Status.OK)

        # Current Python accepts message EOF before RUNNING; future behavior
        # must treat any correction as an explicit compatibility change.
        eof_before_running = _FakeXctraceStream(initial=(None,))
        eof_logger = MagicMock()
        self.assertIsNone(
            await xctrace_drain_until_running(
                stream=eof_before_running,
                logger=eof_logger,
            )
        )
        self.assertTrue(eof_before_running.eof_seen)
        eof_logger.info.assert_not_called()
