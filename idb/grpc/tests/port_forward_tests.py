#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import logging
import socket
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import cast
from unittest.mock import MagicMock, patch

from grpclib.const import Cardinality, Handler, Status
from grpclib.exceptions import GRPCError
from grpclib.server import Stream
from grpclib.testing import ChannelFor
from idb.common.types import IdbException
from idb.grpc.client import Client
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import ForwardPortRequest, ForwardPortResponse
from idb.grpc.port_forward import forward_port
from idb.utils.testing import TestCase


class EchoService:
    def __init__(self, *, eof_first: bool = False) -> None:
        self.eof_first = eof_first
        self.opened = asyncio.Event()
        self.requests: list[tuple[int, bytearray]] = []

    def __mapping__(self) -> dict[str, Handler]:
        return {
            "/idb.CompanionService/forward_port": Handler(
                self.forward_port,
                Cardinality.STREAM_STREAM,
                ForwardPortRequest,
                ForwardPortResponse,
            )
        }

    async def forward_port(
        self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
    ) -> None:
        request = await stream.recv_message()
        if request is None or request.WhichOneof("event") != "open":
            raise GRPCError(Status.INVALID_ARGUMENT)
        data = bytearray()
        self.requests.append((request.open.port, data))
        await stream.send_message(
            ForwardPortResponse(opened=ForwardPortResponse.Opened())
        )
        self.opened.set()
        if self.eof_first:
            return
        while request := await stream.recv_message():
            data.extend(request.data)
            await stream.send_message(ForwardPortResponse(data=request.data))
        await stream.send_message(ForwardPortResponse(data=b"final"))


@asynccontextmanager
async def socket_streams() -> AsyncIterator[
    tuple[
        asyncio.StreamReader,
        asyncio.StreamWriter,
        asyncio.StreamReader,
        asyncio.StreamWriter,
    ]
]:
    left, right = socket.socketpair()
    try:
        bridge_reader, bridge_writer = await asyncio.open_connection(sock=left)
        peer_reader, peer_writer = await asyncio.open_connection(sock=right)
    except BaseException:
        left.close()
        right.close()
        raise
    try:
        yield bridge_reader, bridge_writer, peer_reader, peer_writer
    finally:
        bridge_writer.close()
        peer_writer.close()
        await asyncio.gather(bridge_writer.wait_closed(), peer_writer.wait_closed())


class PortForwardTest(TestCase):
    async def test_completion_before_acknowledgment_preserves_remote_status(
        self,
    ) -> None:
        message = "Forwarding device port 8100 is not allowed"

        class Finished(EchoService):
            def __init__(self, status: Status) -> None:
                self.status = status

            async def forward_port(
                self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
            ) -> None:
                await stream.recv_message()
                await stream.send_initial_metadata()
                # Match a companion that finishes while the request remains open.
                with patch.object(stream._stream, "reset_nowait"):
                    await stream.send_trailing_metadata(
                        status=self.status, status_message=message
                    )
                while await stream.recv_message() is not None:
                    pass

        for status in [Status.PERMISSION_DENIED, Status.OK]:
            with self.subTest(status=status):
                async with (
                    ChannelFor([Finished(status)]) as channel,
                    socket_streams() as streams,
                    asyncio.timeout(5),
                ):
                    reader, writer, _, _ = streams
                    client = Client(
                        stub=CompanionServiceStub(channel),
                        companion=MagicMock(),
                        logger=logging.getLogger(__name__),
                    )
                    with self.assertRaises(IdbException) as raised:
                        await client.forward_port(8100, reader, writer)
                    if status == Status.PERMISSION_DENIED:
                        error = raised.exception.__cause__
                        self.assertIsInstance(error, GRPCError)
                        self.assertEqual(cast(GRPCError, error).status, status)
                        self.assertIn(message, str(raised.exception))
                    else:
                        self.assertIn(
                            "Companion did not acknowledge device port connection",
                            str(raised.exception),
                        )
                    self.assertFalse(writer.is_closing())

    async def test_invalid_ports_fail_before_starting_an_rpc(self) -> None:
        service = EchoService()
        async with ChannelFor([service]) as channel, socket_streams() as streams:
            reader, writer, _, _ = streams
            for port in [-1, 0, 65536]:
                with self.subTest(port=port):
                    with self.assertRaisesRegex(
                        IdbException, "Device port must be in 1...65535"
                    ):
                        await forward_port(
                            CompanionServiceStub(channel), port, reader, writer
                        )
            self.assertFalse(service.opened.is_set())
            self.assertEqual(service.requests, [])
            self.assertFalse(writer.is_closing())

    async def test_drain_timeout_propagates_and_keeps_the_callers_socket_open(
        self,
    ) -> None:
        message = (
            "Device response drain exceeded 4.0 seconds after request-stream completion"
        )

        class DrainTimeout(EchoService):
            async def forward_port(
                self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
            ) -> None:
                await stream.recv_message()
                await stream.send_message(
                    ForwardPortResponse(opened=ForwardPortResponse.Opened())
                )
                while await stream.recv_message() is not None:
                    pass
                await stream.send_message(ForwardPortResponse(data=b"partial"))
                raise GRPCError(Status.DEADLINE_EXCEEDED, message)

        for use_client in [False, True]:
            with self.subTest(use_client=use_client):
                async with (
                    ChannelFor([DrainTimeout()]) as channel,
                    socket_streams() as streams,
                    asyncio.timeout(5),
                ):
                    reader, writer, peer_reader, peer_writer = streams
                    peer_writer.write_eof()
                    stub = CompanionServiceStub(channel)
                    client = Client(
                        stub=stub,
                        companion=MagicMock(),
                        logger=logging.getLogger(__name__),
                    )
                    error_type = IdbException if use_client else GRPCError
                    with self.assertRaises(error_type) as raised:
                        if use_client:
                            await client.forward_port(8099, reader, writer)
                        else:
                            await forward_port(stub, 8099, reader, writer)
                    error = (
                        raised.exception.__cause__ if use_client else raised.exception
                    )
                    self.assertIsInstance(error, GRPCError)
                    self.assertEqual(
                        cast(GRPCError, error).status, Status.DEADLINE_EXCEEDED
                    )
                    self.assertIn(message, str(raised.exception))
                    self.assertEqual(await peer_reader.readexactly(7), b"partial")
                    self.assertFalse(writer.is_closing())

    async def test_binary_transfer_and_final_response_after_client_eof(self) -> None:
        service = EchoService()
        async with ChannelFor([service]) as channel, socket_streams() as streams:
            reader, writer, peer_reader, peer_writer = streams
            task = asyncio.create_task(
                forward_port(CompanionServiceStub(channel), 8099, reader, writer)
            )
            response = asyncio.create_task(peer_reader.read())
            payload = bytes(range(256)) * 2048
            peer_writer.write(payload)
            await peer_writer.drain()
            peer_writer.write_eof()
            await task
            writer.close()
            self.assertEqual(await response, payload + b"final")
            self.assertEqual(service.requests, [(8099, bytearray(payload))])

    async def test_device_eof_finishes_without_waiting_for_client_input(self) -> None:
        service = EchoService(eof_first=True)
        async with ChannelFor([service]) as channel, socket_streams() as streams:
            reader, writer, peer_reader, peer_writer = streams
            task = asyncio.create_task(
                forward_port(CompanionServiceStub(channel), 8100, reader, writer)
            )
            await task
            writer.close()
            self.assertEqual(await peer_reader.read(), b"")
            self.assertEqual(service.requests, [(8100, bytearray())])

    async def test_simultaneous_connections_to_the_same_port_are_independent(
        self,
    ) -> None:
        service = EchoService()
        async with ChannelFor([service]) as channel:
            stub = CompanionServiceStub(channel)

            async def exchange(payload: bytes) -> bytes:
                async with socket_streams() as streams:
                    reader, writer, peer_reader, peer_writer = streams
                    task = asyncio.create_task(forward_port(stub, 8099, reader, writer))
                    peer_writer.write(payload)
                    await peer_writer.drain()
                    peer_writer.write_eof()
                    response = asyncio.create_task(peer_reader.read())
                    await task
                    writer.close()
                    return await response

            results = await asyncio.gather(exchange(b"first"), exchange(b"second"))
            self.assertEqual(results, [b"firstfinal", b"secondfinal"])
            self.assertCountEqual(
                service.requests,
                [(8099, bytearray(b"first")), (8099, bytearray(b"second"))],
            )

    async def test_cancellation_drains_both_copy_tasks(self) -> None:
        service = EchoService()
        async with ChannelFor([service]) as channel, socket_streams() as streams:
            reader, writer, _, _ = streams
            task = asyncio.create_task(
                forward_port(CompanionServiceStub(channel), 8099, reader, writer)
            )
            await service.opened.wait()
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            self.assertTrue(task.cancelled())
            self.assertEqual(len(service.requests), 1)

    async def test_cancellation_after_client_eof_cancels_stalled_response_rpc(
        self,
    ) -> None:
        request_eof = asyncio.Event()
        rpc_cancelled = asyncio.Event()

        class StalledResponse(EchoService):
            async def forward_port(
                self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
            ) -> None:
                await stream.recv_message()
                await stream.send_message(
                    ForwardPortResponse(opened=ForwardPortResponse.Opened())
                )
                while await stream.recv_message() is not None:
                    pass
                request_eof.set()
                try:
                    await asyncio.Event().wait()
                except asyncio.CancelledError:
                    rpc_cancelled.set()
                    raise

        async with (
            ChannelFor([StalledResponse()]) as channel,
            socket_streams() as streams,
            asyncio.timeout(5),
        ):
            reader, writer, _, peer_writer = streams
            task = asyncio.create_task(
                forward_port(CompanionServiceStub(channel), 8099, reader, writer)
            )
            peer_writer.write_eof()
            await request_eof.wait()
            self.assertFalse(task.done())
            task.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await task
            await rpc_cancelled.wait()
            self.assertTrue(task.cancelled())
            self.assertFalse(writer.is_closing())

    async def test_old_companion_fails_without_replaying(self) -> None:
        class Unsupported(EchoService):
            async def forward_port(
                self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
            ) -> None:
                raise GRPCError(Status.UNIMPLEMENTED, "unsupported")

        async with ChannelFor([Unsupported()]) as channel, socket_streams() as streams:
            reader, writer, _, _ = streams
            with self.assertRaises(GRPCError) as raised:
                await forward_port(CompanionServiceStub(channel), 8099, reader, writer)
            self.assertEqual(raised.exception.status, Status.UNIMPLEMENTED)

    async def test_malformed_responses_fail_the_connection(self) -> None:
        class Malformed(EchoService):
            def __init__(self, responses: list[ForwardPortResponse]) -> None:
                self.responses = responses

            async def forward_port(
                self, stream: Stream[ForwardPortRequest, ForwardPortResponse]
            ) -> None:
                await stream.recv_message()
                await stream.send_message(
                    ForwardPortResponse(opened=ForwardPortResponse.Opened())
                )
                for response in self.responses:
                    await stream.send_message(response)
                while await stream.recv_message() is not None:
                    pass

        cases = [
            [ForwardPortResponse()],
            [ForwardPortResponse(opened=ForwardPortResponse.Opened())],
            [ForwardPortResponse(data=b"x" * (64 * 1024 + 1))],
        ]
        for responses in cases:
            with self.subTest(responses=responses):
                async with (
                    ChannelFor([Malformed(responses)]) as channel,
                    socket_streams() as streams,
                ):
                    reader, writer, _, peer_writer = streams
                    peer_writer.write_eof()
                    with self.assertRaises(IdbException):
                        await forward_port(
                            CompanionServiceStub(channel), 8099, reader, writer
                        )

    async def test_slow_local_receiver_applies_backpressure(self) -> None:
        class SlowWriter:
            def __init__(self) -> None:
                self.data: list[bytes] = []
                self.received = asyncio.Event()
                self.release = asyncio.Event()

            def write(self, data: bytes) -> None:
                self.data.append(data)
                self.received.set()

            async def drain(self) -> None:
                await self.release.wait()

        service = EchoService()
        reader = asyncio.StreamReader()
        reader.feed_data(b"request")
        reader.feed_eof()
        writer = SlowWriter()
        async with ChannelFor([service]) as channel:
            task = asyncio.create_task(
                forward_port(
                    CompanionServiceStub(channel),
                    8099,
                    reader,
                    cast(asyncio.StreamWriter, writer),
                )
            )
            await writer.received.wait()
            self.assertEqual(writer.data, [b"request"])
            self.assertFalse(task.done())
            writer.release.set()
            await task
            self.assertEqual(writer.data, [b"request", b"final"])
