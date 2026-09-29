#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import contextlib
import os
import tempfile
from collections.abc import AsyncGenerator
from typing import Any, cast
from unittest import mock

from idb.common.tar import _create_untar_command, generate_tar
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
            # BUG: tar's exit status is never checked, so this streams an empty
            # archive instead of raising TarException -- flipped in the following commit
            chunks = [
                chunk async for chunk in generate_tar([missing], Compression.GZIP)
            ]
            self.assertNotEqual(chunks, [])

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
                # BUG: tar and the compressor are left running -- flipped in the
                # following commit
                self.assertEqual(
                    [process.returncode is None for process in processes],
                    [True, True],
                )
            finally:
                for process in processes:
                    with contextlib.suppress(ProcessLookupError):
                        process.kill()
                    await process.wait()
