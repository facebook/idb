#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import dataclasses
import io
import logging
import os
import stat
import subprocess
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from idb.common.types import Compression
from idb.grpc.idb_pb2 import InstallRequest, InstallResponse
from idb.grpc.install import (
    generate_binary_chunks,
    generate_io_chunks,
    select_stream_compression,
    ZSTD_ZIP_STREAM_MARKER,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
from idb.utils.testing import TestCase


class _Unseekable(io.BytesIO):
    """Makes `zipfile` write data descriptors, as it does to a pipe."""

    def tell(self) -> int:
        raise OSError("unseekable")


def _zip_bytes(
    compression: int = zipfile.ZIP_STORED, buffer: io.BytesIO | None = None
) -> bytes:
    buffer = buffer or io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=compression) as archive:
        archive.writestr(zipfile.ZipInfo("Payload/"), b"")
        archive.writestr(zipfile.ZipInfo("Payload/App.app/"), b"")
        archive.writestr("Payload/App.app/App", b"binary " * 1000)
    return buffer.getvalue()


def _zstd_decompress(stream: bytes) -> bytes:
    return subprocess.run(
        ["zstd", "-dc"], input=stream, capture_output=True, check=True
    ).stdout


class BinaryChunkTests(TestCase):
    async def test_streams_a_read_only_ipa(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "App.ipa")
            with open(path, "wb") as file:
                file.write(b"ipa bytes")
            os.chmod(path, stat.S_IRUSR)
            chunks = generate_binary_chunks(
                path=path,
                destination=InstallRequest.APP,
                compression=None,
                logger=logging.getLogger(__name__),
            )
            self.assertEqual(
                [request.payload.data async for request in chunks], [b"ipa bytes"]
            )


class ZstdZipStreamTests(TestCase):
    async def test_an_ipa_is_marked_and_compressed(self) -> None:
        zip_bytes = _zip_bytes()
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "App.ipa")
            with open(path, "wb") as file:
                file.write(zip_bytes)
            chunks = generate_binary_chunks(
                path=path,
                destination=InstallRequest.APP,
                compression=Compression.ZSTD,
                logger=logging.getLogger(__name__),
                zstd_zip_stream=True,
            )
            stream = b"".join([request.payload.data async for request in chunks])
        self.assertTrue(stream.startswith(ZSTD_ZIP_STREAM_MARKER))
        self.assertLess(len(stream), len(zip_bytes))
        self.assertEqual(_zstd_decompress(stream), zip_bytes)

    async def test_a_zip_read_from_io_is_marked_and_compressed(self) -> None:
        zip_bytes = _zip_bytes()
        chunks = generate_io_chunks(
            io=io.BytesIO(zip_bytes),
            logger=logging.getLogger(__name__),
            zstd_zip_stream=True,
        )
        stream = b"".join([request.payload.data async for request in chunks])
        self.assertTrue(stream.startswith(ZSTD_ZIP_STREAM_MARKER))
        self.assertEqual(_zstd_decompress(stream), zip_bytes)

    async def test_a_deflated_zip_read_from_io_is_sent_as_is(self) -> None:
        zip_bytes = _zip_bytes(zipfile.ZIP_DEFLATED)
        chunks = generate_io_chunks(
            io=io.BytesIO(zip_bytes),
            logger=logging.getLogger(__name__),
            zstd_zip_stream=True,
        )
        self.assertEqual(
            b"".join([request.payload.data async for request in chunks]), zip_bytes
        )

    async def test_a_deflated_zip_with_data_descriptors_is_sent_as_is(self) -> None:
        zip_bytes = _zip_bytes(zipfile.ZIP_DEFLATED, buffer=_Unseekable())
        self.assertTrue(
            zipfile.ZipFile(io.BytesIO(zip_bytes)).infolist()[0].flag_bits & 0x08
        )
        chunks = generate_io_chunks(
            io=io.BytesIO(zip_bytes),
            logger=logging.getLogger(__name__),
            zstd_zip_stream=True,
        )
        self.assertEqual(
            b"".join([request.payload.data async for request in chunks]), zip_bytes
        )

    async def test_a_tar_read_from_io_is_sent_as_is(self) -> None:
        chunks = generate_io_chunks(
            io=io.BytesIO(b"tar bytes"),
            logger=logging.getLogger(__name__),
            zstd_zip_stream=True,
        )
        self.assertEqual(
            [request.payload.data async for request in chunks], [b"tar bytes"]
        )


class InstallZipStreamTests(TestCase):
    async def _install_zip_from_io(self, zstd_zip_streams: bool) -> bytes:
        stream = ScriptedStream(InstallResponse(name="com.example.app"))
        client, _ = make_client("install", stream, is_local=False)
        client.companion = dataclasses.replace(
            client.companion,
            supported_compressions=frozenset({Compression.GZIP, Compression.ZSTD}),
            zstd_zip_streams=zstd_zip_streams,
        )
        with patch("idb.common.tar.has_zstd_compressor", return_value=True):
            async for _ in client.install(bundle=io.BytesIO(_zip_bytes())):
                pass
        return b"".join(
            message.payload.data
            for (message, _) in stream.sent
            if isinstance(message, InstallRequest) and message.payload.data
        )

    async def test_a_zip_is_compressed_for_a_companion_that_accepts_it(self) -> None:
        sent = await self._install_zip_from_io(zstd_zip_streams=True)
        self.assertTrue(sent.startswith(ZSTD_ZIP_STREAM_MARKER))
        self.assertEqual(_zstd_decompress(sent), _zip_bytes())

    async def test_a_zip_is_sent_as_is_to_a_companion_that_does_not(self) -> None:
        sent = await self._install_zip_from_io(zstd_zip_streams=False)
        self.assertEqual(sent, _zip_bytes())


class SelectStreamCompressionTests(unittest.TestCase):
    def test_a_requested_compression_is_used_as_is(self) -> None:
        with patch("idb.common.tar.has_zstd_compressor", return_value=True):
            self.assertEqual(
                select_stream_compression(
                    requested=Compression.GZIP,
                    supported=frozenset({Compression.GZIP, Compression.ZSTD}),
                ),
                Compression.GZIP,
            )

    def test_zstd_is_chosen_when_both_sides_support_it(self) -> None:
        with patch("idb.common.tar.has_zstd_compressor", return_value=True):
            self.assertEqual(
                select_stream_compression(
                    requested=None,
                    supported=frozenset({Compression.GZIP, Compression.ZSTD}),
                ),
                Compression.ZSTD,
            )

    def test_compression_is_left_unset_without_a_local_zstd(self) -> None:
        with patch("idb.common.tar.has_zstd_compressor", return_value=False):
            self.assertEqual(
                select_stream_compression(
                    requested=None,
                    supported=frozenset({Compression.GZIP, Compression.ZSTD}),
                ),
                None,
            )

    def test_compression_is_left_unset_for_a_companion_that_advertises_nothing(
        self,
    ) -> None:
        with patch("idb.common.tar.has_zstd_compressor", return_value=True):
            self.assertEqual(
                select_stream_compression(requested=None, supported=frozenset()),
                None,
            )
