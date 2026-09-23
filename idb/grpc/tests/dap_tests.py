#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import cast
from unittest.mock import AsyncMock

from idb.common.types import (
    Compression,
    FileContainerType,
    FileEntryInfo,
    FileListing,
    IdbException,
)
from idb.grpc.dap import read_next_dap_protocol_message
from idb.grpc.idb_pb2 import DapRequest, DapResponse
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class _Writer:
    def __init__(self) -> None:
        self.data = bytearray()
        self.wrote = asyncio.Event()

    def write(self, data: bytes) -> None:
        self.data.extend(data)
        if data:
            self.wrote.set()


class _DapStream:
    def __init__(self, stdout: bytes) -> None:
        self._responses: asyncio.Queue[DapResponse] = asyncio.Queue()
        self._responses.put_nowait(DapResponse(started=DapResponse.Event(desc="ready")))
        self._stdout = stdout
        self._terminal = DapResponse(stopped=DapResponse.Event(desc="done"))
        self.transcript: list[tuple[str, object | None]] = []
        self.pipe_seen = asyncio.Event()
        self.entered = False
        self.exited = False
        self.end_count = 0

    async def __aenter__(self) -> _DapStream:
        self.entered = True
        return self

    async def __aexit__(self, *_args: object) -> None:
        self.exited = True

    async def send_message(self, message: DapRequest) -> None:
        self.transcript.append(("send", message))
        if message.WhichOneof("control") == "pipe":
            self.pipe_seen.set()
            self._responses.put_nowait(
                DapResponse(stdout=DapResponse.Pipe(data=self._stdout))
            )

    async def recv_message(self) -> DapResponse:
        response = await self._responses.get()
        self.transcript.append(("recv", response))
        return response

    async def end(self) -> None:
        self.end_count += 1
        self.transcript.append(("end", None))
        self._responses.put_nowait(self._terminal)


class DapTests(TestCase):
    async def test_setup_start_pipe_stop_half_close_and_peer_loss(self) -> None:
        path = "/tmp/vscode-debugadapter.zip"
        frame = b"Content-Length: 2\r\n\r\n{}"
        stdout = b'{"event":"initialized"}'
        start = DapRequest(
            start=DapRequest.Start(debugger_pkg_id="vscode-debugadapter")
        )
        pipe = DapRequest(pipe=DapRequest.Pipe(data=frame))
        stop_request = DapRequest(stop=DapRequest.Stop())
        started = DapResponse(started=DapResponse.Event(desc="ready"))
        output = DapResponse(stdout=DapResponse.Pipe(data=stdout))
        stopped = DapResponse(stopped=DapResponse.Event(desc="done"))

        with self.subTest(name="fragmented_body_preserves_python_short_read"):
            header = b"Content-Length: 2\r\n\r\n"
            fragmented = asyncio.StreamReader()
            fragmented.feed_data(header)
            read = asyncio.create_task(read_next_dap_protocol_message(fragmented))
            await asyncio.sleep(0)
            self.assertFalse(read.done())
            fragmented.feed_data(b"{")
            self.assertEqual(await read, header + b"{")
            fragmented.feed_data(b"}")
            self.assertEqual(await fragmented.read(1), b"}")

        cases = [
            ("missing_package", [], Compression.GZIP, True),
            (
                "installed_package",
                [FileEntryInfo(path="vscode-debugadapter")],
                None,
                False,
            ),
        ]
        for name, entries, compression, expects_push in cases:
            with self.subTest(name=name):
                stream = _DapStream(stdout)
                client, open_rpc = make_client("dap", stream)
                client.mkdir = AsyncMock()
                client.ls = AsyncMock(
                    return_value=[FileListing(parent="dap", entries=entries)]
                )
                client.push = AsyncMock()
                reader = asyncio.StreamReader()
                reader.feed_data(frame)
                writer = _Writer()
                stop = asyncio.Event()

                task = asyncio.create_task(
                    client.dap(
                        dap_path=path,
                        input_stream=reader,
                        output_stream=cast(asyncio.StreamWriter, writer),
                        stop=stop,
                        compression=compression,
                    )
                )
                await asyncio.wait_for(stream.pipe_seen.wait(), timeout=1)
                await asyncio.wait_for(writer.wrote.wait(), timeout=1)
                stop.set()
                await task
                await asyncio.sleep(0)

                client.mkdir.assert_awaited_once_with(
                    container=FileContainerType.ROOT,
                    path="dap",
                )
                client.ls.assert_awaited_once_with(
                    container=FileContainerType.ROOT,
                    paths=["dap"],
                )
                if expects_push:
                    client.push.assert_awaited_once_with(
                        src_paths=[str(Path(path).absolute())],
                        container=FileContainerType.ROOT,
                        dest_path="dap",
                        compression=compression,
                    )
                else:
                    client.push.assert_not_awaited()
                self.assertEqual(bytes(writer.data), stdout)
                self.assertEqual(stream.end_count, 1)
                self.assertEqual(
                    stream.transcript,
                    [
                        ("send", start),
                        ("recv", started),
                        ("send", pipe),
                        ("recv", output),
                        ("send", stop_request),
                        ("end", None),
                        ("recv", stopped),
                    ],
                )
                self.assertTrue(stream.entered)
                self.assertTrue(stream.exited)
                open_rpc.assert_called_once_with()

        peer_loss = ScriptedStream[DapResponse]()
        client, open_rpc = make_client("dap", peer_loss)
        client.mkdir = AsyncMock()
        client.ls = AsyncMock(
            return_value=[
                FileListing(
                    parent="dap",
                    entries=[FileEntryInfo(path="vscode-debugadapter")],
                )
            ]
        )
        client.push = AsyncMock()
        with self.subTest(name="peer_loss_before_start"):
            with self.assertRaisesRegex(IdbException, "Failed to spawn dap server"):
                await client.dap(
                    dap_path=path,
                    input_stream=asyncio.StreamReader(),
                    output_stream=cast(asyncio.StreamWriter, _Writer()),
                    stop=asyncio.Event(),
                    compression=None,
                )
            self.assertEqual(
                peer_loss.transcript,
                [("send", start), ("recv", None)],
            )
            self.assertTrue(peer_loss.entered)
            self.assertTrue(peer_loss.exited)
            open_rpc.assert_called_once_with()
