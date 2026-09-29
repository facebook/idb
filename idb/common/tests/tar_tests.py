#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import contextlib
import os
import subprocess
import sys
import tempfile
import unittest
from collections.abc import AsyncGenerator
from typing import Any, cast
from unittest import mock

from idb.common.tar import _create_untar_command, generate_tar, TarException
from idb.common.types import Compression
from idb.utils.testing import TestCase


class UdidTests(TestCase):
    def test_untar_command_gnu(self) -> None:
        output_path = "test_output_path"
        self.assertEqual(
            _create_untar_command(output_path=output_path, gnu_tar=True, verbose=False),
            ["tar", "-C", output_path, "--warning=no-unknown-keyword", "-xzpf", "-"],
        )
        self.assertEqual(
            _create_untar_command(output_path=output_path, gnu_tar=True, verbose=True),
            ["tar", "-C", output_path, "-xzpfv", "-"],
        )

    def test_untar_command_bsd(self) -> None:
        output_path = "test_output_path"
        self.assertEqual(
            _create_untar_command(
                output_path=output_path, gnu_tar=False, verbose=False
            ),
            ["tar", "-C", output_path, "-xzpf", "-"],
        )
        self.assertEqual(
            _create_untar_command(output_path=output_path, gnu_tar=False, verbose=True),
            ["tar", "-C", output_path, "-xzpfv", "-"],
        )


class GenerateTarTests(TestCase):
    async def test_a_path_tar_cannot_read(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = os.path.join(directory, "Missing.app")
            with self.assertRaises(TarException):
                [chunk async for chunk in generate_tar([missing], Compression.GZIP)]

    async def test_closing_the_stream_early(self) -> None:
        processes = []
        spawn = asyncio.create_subprocess_exec

        async def spy(*args: Any, **kwargs: Any) -> asyncio.subprocess.Process:
            process = await spawn(*args, **kwargs)
            processes.append(process)
            return process

        with tempfile.TemporaryDirectory() as directory:
            bundle = os.path.join(directory, "App.app")
            os.mkdir(bundle)
            # Incompressible and larger than the pipes, so neither process can finish
            # unless someone keeps reading.
            with open(os.path.join(bundle, "Payload"), "wb") as file:
                file.write(os.urandom(4 * 1024 * 1024))
            with mock.patch("asyncio.create_subprocess_exec", spy):
                stream = cast(
                    AsyncGenerator[bytes, None],
                    generate_tar([bundle], Compression.GZIP),
                )
                await anext(stream)
                await stream.aclose()
            try:
                self.assertEqual(
                    [process.returncode is None for process in processes],
                    [False, False],
                )
            finally:
                for process in processes:
                    with contextlib.suppress(ProcessLookupError):
                        process.kill()
                    await process.wait()


class ZstdArchiveTests(TestCase):
    @unittest.skipUnless(sys.platform == "darwin", "the padding comes from bsdtar")
    async def test_generates_a_stream_zstd_can_decompress(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bundle = os.path.join(directory, "App.app")
            os.mkdir(bundle)
            with open(os.path.join(bundle, "Info.plist"), "wb") as file:
                file.write(b"plist bytes")
            stream = b"".join(
                [chunk async for chunk in generate_tar([bundle], Compression.ZSTD)]
            )
        decompressed = subprocess.run(
            ["zstd", "-dc"], input=stream, capture_output=True, check=False
        )
        # BUG: bsdtar pads the compressor's output with zeros to its block size, which zstd
        # rejects as an unknown frame — flipped in the following commit.
        self.assertNotEqual(decompressed.returncode, 0, decompressed.stderr)
