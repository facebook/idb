#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
from collections.abc import AsyncIterator
from unittest.mock import MagicMock

from idb.common.types import CompanionInfo, DomainSocketAddress
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import Payload, RecordRequest, RecordResponse
from idb.grpc.video import generate_video_bytes
from idb.utils.testing import TestCase


async def _stream(*responses: RecordResponse) -> AsyncIterator[RecordResponse]:
    for response in responses:
        yield response


def _payload(data: bytes) -> RecordResponse:
    return RecordResponse(payload=Payload(data=data))


def _echo(**kwargs: float) -> RecordResponse:
    # pyre-ignore[6]: the proto constructor is not typed per-field here.
    return RecordResponse(applied=RecordResponse.Applied(**kwargs))


class _FakeStream:
    """Enough of a grpclib stream for `record_video`: it keeps what was sent and replays a fixed
    list of responses, then end-of-stream."""

    def __init__(self, *responses: RecordResponse) -> None:
        self.sent: list[RecordRequest] = []
        self._responses = list(responses)

    async def __aenter__(self) -> "_FakeStream":
        return self

    async def __aexit__(self, *_args: object) -> None:
        return None

    async def send_message(self, message: RecordRequest) -> None:
        self.sent.append(message)

    async def end(self) -> None:
        return None

    async def recv_message(self) -> RecordResponse | None:
        return self._responses.pop(0) if self._responses else None


class RecordVideoTests(TestCase):
    """`record_video` against a fake companion. `is_local` is true so the recording goes to a file
    on the companion's side and the response stream carries only the encode option echo."""

    def setUp(self) -> None:
        super().setUp()
        self.logger = MagicMock()
        self.stop = asyncio.Event()
        # The recording runs until this is set, and these tests are about the request that was sent
        # and the responses that came back, not about the duration.
        self.stop.set()

    async def _record(
        self, stream: _FakeStream, **options: float
    ) -> RecordRequest.Start:
        client = Client.__new__(Client)
        client.stub = MagicMock(record=MagicMock(open=MagicMock(return_value=stream)))
        client.companion = CompanionInfo(
            udid="udid",
            is_local=True,
            pid=None,
            address=DomainSocketAddress(path="/tmp/idb.sock"),
        )
        client.logger = self.logger
        # pyre-ignore[6]: the options are the encode options, each int | float | None.
        await client.record_video(stop=self.stop, output_file="out.mp4", **options)
        return stream.sent[0].start

    async def test_a_request_without_options_is_what_idb_always_sent(self) -> None:
        # This is what the zero default buys: a caller who asks for nothing produces a request
        # indistinguishable from one sent before RecordRequest.Start had these fields.
        start = await self._record(_FakeStream())
        self.assertEqual(start, RecordRequest.Start(file_path="out.mp4"))

    async def test_the_options_reach_the_companion(self) -> None:
        start = await self._record(
            _FakeStream(_echo(fps=15)),
            fps=15,
            scale_factor=0.5,
            bitrate=1000000,
            key_frame_rate=2,
        )
        self.assertEqual(
            start,
            RecordRequest.Start(
                file_path="out.mp4",
                fps=15,
                scale_factor=0.5,
                avg_bitrate=1000000,
                key_frame_rate=2,
            ),
        )

    async def test_a_companion_that_ignored_the_options_is_reported(self) -> None:
        # An old companion drops the unknown fields and records at its own defaults. The missing
        # echo is the only thing that distinguishes that from having honoured them.
        await self._record(_FakeStream(), fps=15)
        self.logger.warning.assert_called_once()

    async def test_an_echoed_option_is_not_reported(self) -> None:
        await self._record(_FakeStream(_echo(fps=15)), fps=15)
        self.logger.warning.assert_not_called()

    async def test_a_default_recording_is_never_reported(self) -> None:
        # Nothing echoes a request that set no options, so warning on one would fire every time.
        await self._record(_FakeStream())
        self.logger.warning.assert_not_called()


class VideoTests(TestCase):
    async def test_the_payloads_are_the_video(self) -> None:
        chunks = [
            chunk
            async for chunk in generate_video_bytes(
                _stream(_payload(b"first"), _payload(b"second"))
            )
        ]
        self.assertEqual(chunks, [b"first", b"second"])

    async def test_the_encode_option_echo_is_not_video(self) -> None:
        # It leads the stream, so yielding it would prepend an empty chunk to the mp4.
        applied: list[RecordResponse.Applied] = []
        chunks = [
            chunk
            async for chunk in generate_video_bytes(
                _stream(_echo(fps=15, scale_factor=0.5), _payload(b"first")), applied
            )
        ]
        self.assertEqual(chunks, [b"first"])
        self.assertEqual([echo.fps for echo in applied], [15])

    async def test_the_echo_is_still_skipped_when_nobody_collects_it(self) -> None:
        chunks = [
            chunk
            async for chunk in generate_video_bytes(
                _stream(_echo(fps=15), _payload(b"first"))
            )
        ]
        self.assertEqual(chunks, [b"first"])
