#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import logging
from collections.abc import AsyncIterator
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import AsyncMock, MagicMock, patch

from idb.common.types import CompanionInfo, IdbException, TCPAddress
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import InjectAudioResponse
from idb.utils.testing import TestCase


def _client(is_local: bool) -> tuple[Client, MagicMock, MagicMock]:
    stream = MagicMock()
    stream.__aenter__ = AsyncMock(return_value=stream)
    stream.__aexit__ = AsyncMock(return_value=None)
    stream.send_message = AsyncMock()
    stream.end = AsyncMock()
    stream.recv_message = AsyncMock(return_value=InjectAudioResponse())

    stub = MagicMock()
    stub.inject_audio.open = MagicMock(return_value=stream)
    client = Client(
        stub=stub,
        companion=CompanionInfo(
            udid="test",
            is_local=is_local,
            pid=None,
            address=TCPAddress(host="localhost", port=10882),
        ),
        logger=logging.getLogger(__name__),
    )
    return client, stub, stream


class InjectAudioTest(TestCase):
    async def test_local_client_sends_one_absolute_file_path(self) -> None:
        client, stub, stream = _client(is_local=True)
        with TemporaryDirectory() as directory:
            audio = Path(directory) / "sample.wav"
            audio.write_bytes(b"wave")

            await client.inject_audio(str(audio))

        stub.inject_audio.open.assert_called_once_with()
        request = stream.send_message.await_args.args[0]
        self.assertEqual(request.payload.WhichOneof("source"), "file_path")
        self.assertEqual(request.payload.file_path, str(audio.resolve()))
        stream.end.assert_awaited_once_with()
        stream.recv_message.assert_awaited_once_with()

    async def test_remote_client_streams_raw_file_bytes(self) -> None:
        client, stub, stream = _client(is_local=False)
        with TemporaryDirectory() as directory:
            audio = Path(directory) / "sample.wav"
            audio.write_bytes(b"wave")
            await client.inject_audio(str(audio))

        stub.inject_audio.open.assert_called_once_with()
        requests = [call.args[0] for call in stream.send_message.await_args_list]
        self.assertEqual([request.payload.data for request in requests], [b"wave"])
        self.assertTrue(
            all(request.payload.WhichOneof("source") == "data" for request in requests)
        )
        stream.end.assert_awaited_once_with()
        stream.recv_message.assert_awaited_once_with()

        # A file that cannot be read is reported as such, not as a lost companion.
        async def unreadable(file_path: str) -> AsyncIterator[bytes]:
            raise PermissionError(13, "Permission denied", file_path)
            yield b""

        client, _, _ = _client(is_local=False)
        with TemporaryDirectory() as directory:
            audio = Path(directory) / "sample.wav"
            audio.write_bytes(b"wave")
            with patch("idb.grpc.client.generate_file_chunks", unreadable):
                with self.assertRaisesRegex(IdbException, "Could not read"):
                    await client.inject_audio(str(audio))

    async def test_rejects_non_files_before_opening_the_rpc(self) -> None:
        for is_local in [True, False]:
            client, stub, _ = _client(is_local=is_local)
            with TemporaryDirectory() as directory:
                with self.assertRaisesRegex(IdbException, "not a regular file"):
                    await client.inject_audio(directory)
            stub.inject_audio.open.assert_not_called()

    async def test_rejects_a_missing_file_before_opening_the_rpc(self) -> None:
        client, stub, _ = _client(is_local=True)

        with TemporaryDirectory() as directory:
            with self.assertRaisesRegex(IdbException, "not a regular file"):
                await client.inject_audio(str(Path(directory) / "missing.wav"))

        stub.inject_audio.open.assert_not_called()
