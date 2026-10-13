#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import json
import logging
import sys
from argparse import ArgumentParser, Namespace
from asyncio import StreamReader, StreamWriter

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import Client, IdbConnectionException, IdbException

MAX_CONNECTIONS = 64


class ForwardListener:
    """Owns accepted sockets and their RPC tasks; shutdown drains every task."""

    def __init__(
        self, client: Client, device_port: int, logger: logging.Logger
    ) -> None:
        self.client = client
        self.device_port = device_port
        self.logger = logger
        self.tasks: dict[asyncio.Task[None], StreamWriter] = {}
        self.closed = False
        self.capacity_reported = False

    def accept(self, reader: StreamReader, writer: StreamWriter) -> None:
        if self.closed:
            self.logger.debug(
                "Rejecting forwarding connection during listener shutdown"
            )
            writer.transport.abort()
            return
        if len(self.tasks) >= MAX_CONNECTIONS:
            if not self.capacity_reported:
                self.logger.warning(
                    "Rejecting forwarding connections: reached the limit of %s active connections",
                    MAX_CONNECTIONS,
                )
                self.capacity_reported = True
            writer.transport.abort()
            return
        task = asyncio.create_task(self._forward(reader, writer))
        self.tasks[task] = writer
        task.add_done_callback(self._finished)

    def _finished(self, task: asyncio.Task[None]) -> None:
        writer = self.tasks.pop(task)
        self.capacity_reported = False
        if task.cancelled():
            writer.transport.abort()
        elif error := task.exception():
            writer.transport.abort()
            self.logger.error("Unexpected forwarding failure: %s", error)

    async def _forward(self, reader: StreamReader, writer: StreamWriter) -> None:
        try:
            await self.client.forward_port(self.device_port, reader, writer)
        except (IdbException, IdbConnectionException, OSError) as error:
            writer.transport.abort()
            self.logger.warning("Device port forwarding failed: %s", error)
        except asyncio.CancelledError:
            writer.transport.abort()
            raise
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                # Socket errors were already reported by the forwarding operation.
                self.logger.debug("Forwarded socket failed during close", exc_info=True)

    async def close(self) -> None:
        self.closed = True
        tasks = list(self.tasks)
        for task, writer in list(self.tasks.items()):
            writer.transport.abort()
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)


class ForwardCommand(ClientCommand):
    @property
    def name(self) -> str:
        return "forward"

    @property
    def description(self) -> str:
        return "Forward a local TCP listener to a physical device port through idb"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument("device_port", type=int)
        parser.add_argument("--local-port", type=int, default=0)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        if not 1 <= args.device_port <= 65535:
            raise IdbException("Device port must be in 1...65535")
        if not 0 <= args.local_port <= 65535:
            raise IdbException("Local port must be in 0...65535")
        listener = ForwardListener(client, args.device_port, self.logger)
        stop = signal_handler_event("port forwarding")
        server = await asyncio.start_server(
            listener.accept,
            "127.0.0.1",
            args.local_port,
            start_serving=False,
            limit=64 * 1024,
        )
        try:
            await server.start_serving()
            port = server.sockets[0].getsockname()[1]
            ready = {
                "event": "ready",
                "host_port": port,
                "device_port": args.device_port,
            }
            output = (
                json.dumps(ready)
                if args.json
                else f"127.0.0.1:{port} -> device:{args.device_port}"
            )
            sys.stdout.write(output + "\n")
            sys.stdout.flush()
            await stop.wait()
        finally:
            server.close()
            await listener.close()
            await server.wait_closed()
