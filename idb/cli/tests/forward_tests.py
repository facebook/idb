#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import io
import json
import logging
import socket
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch

from idb.cli.command_tree import build_command_graph
from idb.cli.commands.forward import ForwardCommand, ForwardListener
from idb.common.types import Client, IdbException
from idb.utils.testing import TestCase


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
    reader, writer = await asyncio.open_connection(sock=left)
    peer_reader, peer_writer = await asyncio.open_connection(sock=right)
    try:
        yield reader, writer, peer_reader, peer_writer
    finally:
        writer.close()
        peer_writer.close()
        await asyncio.gather(writer.wait_closed(), peer_writer.wait_closed())


@asynccontextmanager
async def tcp_streams(
    port: int,
) -> AsyncIterator[tuple[asyncio.StreamReader, asyncio.StreamWriter]]:
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    try:
        yield reader, writer
    finally:
        writer.close()
        await writer.wait_closed()


class ForwardTest(TestCase):
    async def test_invalid_ports_fail_before_listener_creation(self) -> None:
        parser = build_command_graph().parser
        for device_port, local_port, message in [
            (0, 0, "Device port must be in 1...65535"),
            (-1, 0, "Device port must be in 1...65535"),
            (65536, 0, "Device port must be in 1...65535"),
            (1, -1, "Local port must be in 0...65535"),
            (1, 65536, "Local port must be in 0...65535"),
        ]:
            with self.subTest(device_port=device_port, local_port=local_port):
                args = parser.parse_args(
                    ["forward", str(device_port), "--local-port", str(local_port)]
                )
                client = MagicMock(spec=Client)
                with patch(
                    "idb.cli.commands.forward.asyncio.start_server", new=AsyncMock()
                ) as start_server:
                    with self.assertRaisesRegex(IdbException, message):
                        await ForwardCommand().run_with_client(args, client)
                start_server.assert_not_called()
                client.forward_port.assert_not_called()

    async def test_valid_port_boundaries_create_listener(self) -> None:
        parser = build_command_graph().parser
        stop = asyncio.Event()
        stop.set()
        for device_port, local_port in [(1, 0), (65535, 65535)]:
            with self.subTest(device_port=device_port, local_port=local_port):
                args = parser.parse_args(
                    ["forward", str(device_port), "--local-port", str(local_port)]
                )
                server = MagicMock()
                server.start_serving = AsyncMock()
                server.wait_closed = AsyncMock()
                with (
                    patch(
                        "idb.cli.commands.forward.asyncio.start_server",
                        new=AsyncMock(return_value=server),
                    ) as start_server,
                    patch(
                        "idb.cli.commands.forward.signal_handler_event",
                        return_value=stop,
                    ),
                    patch("idb.cli.commands.forward.sys.stdout", io.StringIO()),
                ):
                    await ForwardCommand().run_with_client(
                        args, cast(Client, MagicMock(spec=Client))
                    )
                self.assertEqual(
                    start_server.call_args.args[1:], ("127.0.0.1", local_port)
                )
                server.start_serving.assert_awaited_once()
                server.close.assert_called_once()
                server.wait_closed.assert_awaited_once()

    @patch("idb.cli.commands.forward.MAX_CONNECTIONS", 1)
    async def test_connection_limit_rejects_peer_and_preserves_active_forward(
        self,
    ) -> None:
        started = asyncio.Event()

        async def forward(
            _port: int, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
        ) -> None:
            started.set()
            while data := await reader.read(1024):
                writer.write(data)
                await writer.drain()

        client = MagicMock(spec=Client)
        client.forward_port = AsyncMock(side_effect=forward)
        logger = MagicMock(spec=logging.Logger)
        listener = ForwardListener(client, 8099, logger)
        server = await asyncio.start_server(listener.accept, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        try:
            async with asyncio.timeout(5), tcp_streams(port) as (reader, writer):
                await started.wait()
                async with tcp_streams(port) as (rejected_reader, _):
                    self.assertEqual(await rejected_reader.read(), b"")
                    logger.warning.assert_called_once()
                    self.assertIn("limit", logger.warning.call_args.args[0])
                    client.forward_port.assert_awaited_once()
                    self.assertEqual(len(listener.tasks), 1)
                    async with tcp_streams(port) as (another_rejected_reader, _):
                        self.assertEqual(await another_rejected_reader.read(), b"")
                    logger.warning.assert_called_once()
                    writer.write(b"still forwarding")
                    await writer.drain()
                    self.assertEqual(
                        await reader.readexactly(len(b"still forwarding")),
                        b"still forwarding",
                    )
                    active_task = next(iter(listener.tasks))
                    writer.close()
                    await writer.wait_closed()
                    await active_task
                    self.assertFalse(listener.tasks)
                    started.clear()
                    async with tcp_streams(port) as (next_reader, next_writer):
                        await started.wait()
                        self.assertEqual(client.forward_port.await_count, 2)
                        logger.warning.assert_called_once()
                        for _ in range(2):
                            async with tcp_streams(port) as (rejected_reader, _):
                                self.assertEqual(await rejected_reader.read(), b"")
                            self.assertEqual(logger.warning.call_count, 2)
                        next_writer.write(b"forwarding after capacity recovered")
                        await next_writer.drain()
                        self.assertEqual(
                            await next_reader.readexactly(
                                len(b"forwarding after capacity recovered")
                            ),
                            b"forwarding after capacity recovered",
                        )
                    server.close()
                    await listener.close()
                    await server.wait_closed()
        finally:
            server.close()
            async with asyncio.timeout(5):
                await listener.close()
                await server.wait_closed()
        self.assertFalse(listener.tasks)

    async def test_closed_listener_rejects_peer_and_allows_server_shutdown(
        self,
    ) -> None:
        client = MagicMock(spec=Client)
        logger = MagicMock(spec=logging.Logger)
        listener = ForwardListener(client, 8099, logger)
        await listener.close()
        server = await asyncio.start_server(listener.accept, "127.0.0.1", 0)
        port = server.sockets[0].getsockname()[1]
        try:
            async with asyncio.timeout(5), tcp_streams(port) as (reader, _):
                self.assertEqual(await reader.read(), b"")
                logger.debug.assert_called_once()
                self.assertIn("shutdown", logger.debug.call_args.args[0])
                logger.warning.assert_not_called()
                client.forward_port.assert_not_called()
                self.assertFalse(listener.tasks)
                server.close()
                await server.wait_closed()
        finally:
            server.close()
            async with asyncio.timeout(5):
                await server.wait_closed()

    async def test_shutdown_before_forward_task_starts_closes_accepted_socket(
        self,
    ) -> None:
        client = MagicMock(spec=Client)
        listener = ForwardListener(client, 8099, logging.getLogger(__name__))
        async with socket_streams() as streams:
            reader, writer, peer_reader, _ = streams
            listener.accept(reader, writer)
            await listener.close()
            self.assertEqual(await peer_reader.read(), b"")
            self.assertFalse(listener.tasks)
            client.forward_port.assert_not_called()

    async def test_shutdown_cancels_active_forwarding(self) -> None:
        started = asyncio.Event()
        cancelled = asyncio.Event()

        async def forward(*_args: object) -> None:
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

        client = MagicMock(spec=Client)
        client.forward_port = AsyncMock(side_effect=forward)
        listener = ForwardListener(client, 8099, logging.getLogger(__name__))
        async with socket_streams() as streams:
            reader, writer, peer_reader, _ = streams
            listener.accept(reader, writer)
            await started.wait()
            await listener.close()
            self.assertTrue(cancelled.is_set())
            self.assertEqual(await peer_reader.read(), b"")
            self.assertFalse(listener.tasks)
            client.forward_port.assert_awaited_once_with(8099, reader, writer)

    async def test_parser_and_machine_readable_listener_readiness(self) -> None:
        args = build_command_graph().parser.parse_args(
            ["forward", "8099", "--local-port", "0", "--json"]
        )
        self.assertEqual(args.device_port, 8099)
        stop = asyncio.Event()
        stop.set()
        server = MagicMock()
        server.start_serving = AsyncMock()
        server.wait_closed = AsyncMock()
        server.sockets[0].getsockname.return_value = ("127.0.0.1", 41234)
        output = io.StringIO()
        with (
            patch(
                "idb.cli.commands.forward.asyncio.start_server",
                new=AsyncMock(return_value=server),
            ),
            patch("idb.cli.commands.forward.signal_handler_event", return_value=stop),
            patch("idb.cli.commands.forward.sys.stdout", output),
        ):
            await ForwardCommand().run_with_client(
                args, cast(Client, MagicMock(spec=Client))
            )
        self.assertEqual(
            json.loads(output.getvalue()),
            {"event": "ready", "host_port": 41234, "device_port": 8099},
        )
        server.start_serving.assert_awaited_once()

    async def test_command_shutdown_closes_connections_and_releases_port(self) -> None:
        started = asyncio.Event()
        cancelled = asyncio.Event()
        ready = asyncio.Event()
        stop = asyncio.Event()

        async def forward(*_args: object) -> None:
            started.set()
            try:
                await asyncio.Event().wait()
            finally:
                cancelled.set()

        client = MagicMock(spec=Client)
        client.forward_port = AsyncMock(side_effect=forward)
        args = build_command_graph().parser.parse_args(["forward", "8099", "--json"])
        output = io.StringIO()
        peer_writer = None
        with (
            patch("idb.cli.commands.forward.signal_handler_event", return_value=stop),
            patch("idb.cli.commands.forward.sys.stdout", output),
            patch.object(output, "flush", ready.set),
        ):
            command = asyncio.create_task(
                ForwardCommand().run_with_client(args, client)
            )
            try:
                async with asyncio.timeout(5):
                    await ready.wait()
                    port = json.loads(output.getvalue())["host_port"]
                    peer_reader, peer_writer = await asyncio.open_connection(
                        "127.0.0.1", port
                    )
                    await started.wait()
                    stop.set()
                    await command
                    self.assertTrue(cancelled.is_set())
                    self.assertEqual(await peer_reader.read(), b"")
            finally:
                command.cancel()
                await asyncio.gather(command, return_exceptions=True)
                if peer_writer is not None:
                    peer_writer.close()
                    await peer_writer.wait_closed()
        async with await asyncio.start_server(
            lambda _reader, writer: writer.close(), "127.0.0.1", port
        ) as server:
            self.assertEqual(server.sockets[0].getsockname()[1], port)
