#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import logging
import os
import stat
import tempfile
import unittest
from unittest.mock import patch

from idb.common.types import Compression
from idb.grpc.idb_pb2 import InstallRequest
from idb.grpc.install import generate_binary_chunks, select_stream_compression
from idb.utils.testing import TestCase


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
