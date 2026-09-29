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

from idb.grpc.idb_pb2 import InstallRequest
from idb.grpc.install import generate_binary_chunks
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
            # BUG: the .ipa is opened read-write, so a read-only .ipa (such as a
            # build output) cannot be streamed — flipped in the following commit.
            with self.assertRaises(PermissionError):
                [request async for request in chunks]
