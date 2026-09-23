#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

from collections.abc import Awaitable, Callable

from idb.grpc.idb_pb2 import DebugServerRequest, DebugServerResponse
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class DebugServerTests(TestCase):
    async def test_start_stop_status_request_response_and_half_close(self) -> None:
        status = DebugServerResponse.Status(
            lldb_bootstrap_commands=[
                "platform select remote-ios",
                "process connect connect://127.0.0.1:1234",
            ]
        )
        populated = DebugServerResponse(status=status)
        absent = DebugServerResponse(pipe=DebugServerResponse.Pipe(data=b"ignored"))
        extra = DebugServerResponse(
            status=DebugServerResponse.Status(lldb_bootstrap_commands=["unconsumed"])
        )
        cases: list[
            tuple[
                str,
                DebugServerRequest,
                list[DebugServerResponse],
                Callable[[object], Awaitable[object]],
                object,
            ]
        ] = [
            (
                "start",
                DebugServerRequest(
                    start=DebugServerRequest.Start(bundle_id="com.example.App")
                ),
                [populated, extra],
                lambda client: client.debugserver_start("com.example.App"),
                [
                    "platform select remote-ios",
                    "process connect connect://127.0.0.1:1234",
                ],
            ),
            (
                "stop",
                DebugServerRequest(stop=DebugServerRequest.Stop()),
                [DebugServerResponse()],
                lambda client: client.debugserver_stop(),
                None,
            ),
            (
                "status_running",
                DebugServerRequest(status=DebugServerRequest.Status()),
                [populated],
                lambda client: client.debugserver_status(),
                [
                    "platform select remote-ios",
                    "process connect connect://127.0.0.1:1234",
                ],
            ),
            (
                "status_absent_arm",
                DebugServerRequest(status=DebugServerRequest.Status()),
                [absent],
                lambda client: client.debugserver_status(),
                None,
            ),
        ]

        for name, request, responses, invoke, expected in cases:
            with self.subTest(name=name):
                stream = ScriptedStream[DebugServerResponse](*responses)
                client, open_rpc = make_client("debugserver", stream)
                actual = await invoke(client)
                if isinstance(actual, list):
                    actual = list(actual)
                self.assertEqual(actual, expected)
                self.assertEqual(
                    stream.transcript,
                    [
                        ("send", request),
                        ("end", None),
                        ("recv", responses[0]),
                    ],
                )
                self.assertTrue(stream.entered)
                self.assertTrue(stream.exited)
                open_rpc.assert_called_once_with()
                if len(responses) == 2:
                    self.assertEqual(await stream.recv_message(), extra)
