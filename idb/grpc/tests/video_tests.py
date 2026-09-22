#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
from collections.abc import AsyncIterator
from unittest.mock import MagicMock, patch

from idb.common.types import CompanionInfo, DomainSocketAddress, VideoFormat
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import (
    Payload,
    RecordRequest,
    RecordResponse,
    VideoStreamRequest,
    VideoStreamResponse,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
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

    async def test_local_and_remote_stop_and_publication_transcript(self) -> None:
        applied = _echo(
            fps=15,
            scale_factor=0.5,
            avg_bitrate=1_000_000,
            key_frame_rate=2,
        )
        first = _payload(b"first")
        second = _payload(b"second")

        for name, is_local, output_file in (
            ("local_path", True, "out.mp4"),
            ("local_dash", True, "-"),
            ("remote_path", False, "out.mp4"),
            ("remote_dash", False, "-"),
        ):
            with self.subTest(name=name):
                terminal = RecordResponse(log_output=output_file.encode())
                responses = (
                    (applied, terminal) if is_local else (applied, first, second)
                )
                stream = ScriptedStream[RecordResponse](*responses)
                client, open_rpc = make_client(
                    "record",
                    stream,
                    is_local=is_local,
                )
                publications: list[tuple[str, list[bytes]]] = []

                async def publish(
                    stream: AsyncIterator[bytes],
                    output_path: str,
                    publication_log: list[tuple[str, list[bytes]]] = publications,
                ) -> None:
                    publication_log.append(
                        (output_path, [chunk async for chunk in stream])
                    )

                with patch("idb.grpc.client.drain_gzip_decompress", new=publish):
                    await client.record_video(
                        stop=self.stop,
                        output_file=output_file,
                        fps=15,
                        scale_factor=0.5,
                        bitrate=1_000_000,
                        key_frame_rate=2,
                    )

                start = RecordRequest(
                    start=RecordRequest.Start(
                        file_path=output_file if is_local else "",
                        fps=15,
                        scale_factor=0.5,
                        avg_bitrate=1_000_000,
                        key_frame_rate=2,
                    )
                )
                prefix = [
                    ("send", start),
                    ("send", RecordRequest(stop=RecordRequest.Stop())),
                    ("end", None),
                ]
                expected_transcript = (
                    prefix + [("recv", applied), ("recv", terminal)]
                    if is_local
                    else prefix
                    + [
                        ("recv", applied),
                        ("recv", first),
                        ("recv", second),
                        ("recv", None),
                    ]
                )
                self.assertEqual(stream.transcript, expected_transcript)
                self.assertEqual(
                    publications,
                    [] if is_local else [(output_file, [b"first", b"second"])],
                )
                open_rpc.assert_called_once_with()
                client.logger.warning.assert_not_called()


class VideoStreamTests(TestCase):
    async def test_start_payload_stop_and_output_destination(self) -> None:
        first = VideoStreamResponse(payload=Payload(data=b"first"))
        second = VideoStreamResponse(payload=Payload(data=b"second"))

        for name, is_local, output_file in (
            ("local_stdout", True, None),
            ("local_file", True, "out.h264"),
            ("local_dash", True, "-"),
            ("remote_stdout", False, None),
            ("remote_file", False, "out.h264"),
            ("remote_dash", False, "-"),
        ):
            with self.subTest(name=name):
                responses = (
                    () if is_local and output_file is not None else (first, second)
                )
                stream = ScriptedStream[VideoStreamResponse](*responses)
                client, open_rpc = make_client(
                    "video_stream",
                    stream,
                    is_local=is_local,
                )
                publications: list[tuple[str, list[bytes]]] = []

                async def publish(
                    stream: AsyncIterator[bytes],
                    file_path: str,
                    publication_log: list[tuple[str, list[bytes]]] = publications,
                ) -> None:
                    publication_log.append(
                        (file_path, [chunk async for chunk in stream])
                    )

                with patch("idb.grpc.client.drain_to_file", new=publish):
                    output = [
                        chunk
                        async for chunk in client.stream_video(
                            output_file=output_file,
                            fps=15,
                            format=VideoFormat.H264,
                            compression_quality=0.2,
                            scale_factor=0.5,
                        )
                    ]

                start = VideoStreamRequest(
                    start=VideoStreamRequest.Start(
                        file_path=(
                            output_file if is_local and output_file is not None else ""
                        ),
                        fps=15,
                        format=VideoStreamRequest.H264,
                        compression_quality=0.2,
                        scale_factor=0.5,
                    )
                )
                self.assertEqual(
                    stream.transcript,
                    [
                        ("send", start),
                        *[("recv", response) for response in responses],
                        ("recv", None),
                        ("send", VideoStreamRequest(stop=VideoStreamRequest.Stop())),
                        ("end", None),
                    ],
                )
                self.assertEqual(
                    output,
                    [b"first", b"second"] if output_file is None else [],
                )
                self.assertEqual(
                    publications,
                    (
                        [(output_file, [b"first", b"second"])]
                        if not is_local and output_file is not None
                        else []
                    ),
                )
                open_rpc.assert_called_once_with()


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
