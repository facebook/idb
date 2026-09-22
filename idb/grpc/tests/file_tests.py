#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio

from idb.grpc.idb_pb2 import (
    FileContainer as GrpcFileContainer,
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
