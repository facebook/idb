#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import sys
from argparse import ArgumentParser, Namespace
from asyncio import StreamReader, StreamWriter
from dataclasses import dataclass

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import Client, Compression


@dataclass
class StdStreams:
    stdin: StreamReader
    stdout: StreamWriter
    stderr: StreamWriter


class DapCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Spawn a new debug server using VSCode DAP protocol "

    @property
    def name(self) -> str:
        return "dap"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "dap_pkg_path", help="Path of the dap package to install", type=str
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )
        stdStreams = await get_std_as_streams()
        await client.dap(
            dap_path=args.dap_pkg_path,
            input_stream=stdStreams.stdin,
            output_stream=stdStreams.stdout,
            stop=signal_handler_event("dap"),
            compression=compression,
        )


async def get_std_as_streams() -> StdStreams:
    """
    Connect stdin, stdout and stderr as Streams.
    Makes stdin available for reading and stdout and stderr for writing.
    """

    loop = asyncio.get_event_loop()
    stdin = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(stdin)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    stdout_transport, stdout_protocol = await loop.connect_write_pipe(
        asyncio.streams.FlowControlMixin, sys.stdout
    )
    stdout = asyncio.StreamWriter(stdout_transport, stdout_protocol, stdin, loop)
    stderr_transport, stderr_protocol = await loop.connect_write_pipe(
        asyncio.streams.FlowControlMixin, sys.stderr
    )
    stderr = asyncio.StreamWriter(stderr_transport, stderr_protocol, stdin, loop)
    return StdStreams(
        stdin=stdin,
        stdout=stdout,
        stderr=stderr,
    )
