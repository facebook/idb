#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import dataclasses
from collections.abc import AsyncIterator
from unittest.mock import patch

from idb.common.types import Compression, FileContainerType
from idb.grpc.idb_pb2 import (
    FileContainer as GrpcFileContainer,
    Payload,
    PushRequest,
    PushResponse,
    TailRequest,
    TailResponse,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class TailTests(TestCase):
    async def test_start_bytes_cancel_before_stop_without_half_close(
        self,
    ) -> None:
        stream = ScriptedStream(
            TailResponse(data=b"bytes"),
            block_after_responses=True,
        )
        client, open_rpc = make_client("tail", stream)
        stop = asyncio.Event()
        iterator = client.tail(
            stop=stop,
            container="com.example.app",
            path="Library/example.log",
        )

        self.assertEqual(await anext(iterator), b"bytes")
        stop.set()
        with self.assertRaises(StopAsyncIteration):
            await anext(iterator)

        start = TailRequest(
            start=TailRequest.Start(
                container=GrpcFileContainer(
                    kind=GrpcFileContainer.APPLICATION,
                    bundle_id="com.example.app",
                ),
                path="Library/example.log",
            )
        )
        stop_request = TailRequest(stop=TailRequest.Stop())
        self.assertEqual(
            stream.sent,
            [(start, False), (stop_request, False)],
        )
        self.assertEqual(
            [
                (action, payload)
                for action, payload in stream.transcript
                if action in {"send", "cancel", "end"}
            ],
            [
                ("send", start),
                ("cancel", None),
                ("send", stop_request),
            ],
        )
        self.assertEqual(stream.read_cancellations, 1)
        self.assertNotIn(("end", None), stream.transcript)
        open_rpc.assert_called_once_with()
        self.assertTrue(stream.entered)
        self.assertTrue(stream.exited)


class PushTests(TestCase):
    async def _push_to_a_zstd_companion(
        self, compression: Compression | None
    ) -> tuple[ScriptedStream[PushResponse], list[Compression]]:
        return await self._push(
            compression, supported=frozenset({Compression.GZIP, Compression.ZSTD})
        )

    async def _push(
        self, compression: Compression | None, supported: frozenset[Compression]
    ) -> tuple[ScriptedStream[PushResponse], list[Compression]]:
        stream = ScriptedStream(PushResponse())
        client, _ = make_client("push", stream, is_local=False)
        client.companion = dataclasses.replace(
            client.companion, supported_compressions=supported
        )
        tarred_with: list[Compression] = []

        async def generate_tar(
            paths: list[str], compression: Compression, verbose: bool
        ) -> AsyncIterator[bytes]:
            tarred_with.append(compression)
            yield b"tar"

        with (
            patch("idb.grpc.client.generate_tar", generate_tar),
            patch("idb.common.tar.has_zstd_compressor", return_value=True),
        ):
            await client.push(
                src_paths=["file.txt"],
                container=FileContainerType.MEDIA,
                dest_path="dest",
                compression=compression,
            )
        return (stream, tarred_with)

    def _payloads(self, stream: ScriptedStream[PushResponse]) -> list[Payload]:
        return [
            message.payload
            for (message, _) in stream.sent
            if isinstance(message, PushRequest) and message.HasField("payload")
        ]

    async def test_a_requested_compression_is_sent_and_used(self) -> None:
        (stream, tarred_with) = await self._push_to_a_zstd_companion(Compression.GZIP)
        self.assertEqual(tarred_with, [Compression.GZIP])
        self.assertEqual(
            self._payloads(stream),
            [Payload(compression=Payload.GZIP), Payload(data=b"tar")],
        )

    async def test_no_requested_compression_to_a_gzip_companion(self) -> None:
        (stream, tarred_with) = await self._push(
            None, supported=frozenset({Compression.GZIP})
        )
        self.assertEqual(tarred_with, [Compression.GZIP])
        self.assertEqual(self._payloads(stream), [Payload(data=b"tar")])

    async def test_no_requested_compression_to_a_zstd_companion(self) -> None:
        (stream, tarred_with) = await self._push_to_a_zstd_companion(None)
        self.assertEqual(tarred_with, [Compression.ZSTD])
        self.assertEqual(
            self._payloads(stream),
            [Payload(compression=Payload.ZSTD), Payload(data=b"tar")],
        )
