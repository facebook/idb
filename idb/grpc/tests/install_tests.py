#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import dataclasses
import functools
import io
import logging
import os
import stat
import subprocess
import tempfile
import unittest
import zipfile
from unittest.mock import patch

from idb.common.types import Compression, FileContainerType
from idb.grpc.idb_pb2 import InstallRequest, InstallResponse, Payload
from idb.grpc.install import (
    generate_binary_chunks,
    generate_io_chunks,
    MIB,
    remaining_size,
    select_stream_compression,
    UploadProgress,
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


def _frame(message: InstallRequest) -> str:
    value = message.WhichOneof("value")
    if value != "payload":
        return value
    source = message.payload.WhichOneof("source")
    if source == "compression":
        return f"compression:{Payload.Compression.Name(message.payload.compression)}"
    if source == "data":
        if message.payload.data.startswith(b"\x1f\x8b"):
            return "data:gzip"
        if message.payload.data.startswith(b"\x28\xb5\x2f\xfd"):
            return "data:zstd"
    return source


class InstallFrameOrderTests(TestCase):
    """The companion reads every option frame before the payload, in a fixed order:
    destination, name_hint, make_debuggable, override_modification_time,
    skip_signing_bundles, link_dsym_to_bundle, then compression and the payload."""

    async def _frames(
        self, install: str, *, is_local: bool, **kwargs: object
    ) -> list[str]:
        stream = ScriptedStream(InstallResponse(name="installed"))
        client, _ = make_client("install", stream, is_local=is_local)
        client.companion = dataclasses.replace(
            client.companion,
            supported_compressions=frozenset({Compression.GZIP, Compression.ZSTD}),
        )
        with patch("idb.common.tar.has_zstd_compressor", return_value=True):
            async for _ in getattr(client, install)(**kwargs):
                pass
        frames = []
        for message, _ in stream.sent:
            frame = _frame(message)
            if not frames or frame != frames[-1] or not frame.startswith("data"):
                frames.append(frame)
        return frames

    async def test_a_remote_dylib(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dylib = os.path.join(directory, "libExample.dylib")
            with open(dylib, "wb") as f:
                f.write(b"dylib")
            frames = await self._frames("install_dylib", is_local=False, dylib=dylib)
        self.assertEqual(frames, ["destination", "name_hint", "data:gzip"])

    async def test_a_remote_xctest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            xctest = os.path.join(directory, "Example.xctest")
            os.mkdir(xctest)
            frames = await self._frames("install_xctest", is_local=False, xctest=xctest)
        self.assertEqual(frames, ["destination", "data:gzip"])

    async def test_a_remote_framework(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            framework = os.path.join(directory, "Example.framework")
            os.mkdir(framework)
            frames = await self._frames(
                "install_framework", is_local=False, framework_path=framework
            )
        self.assertEqual(frames, ["destination", "data:gzip"])

    async def test_a_dsym_linked_to_a_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dsym = os.path.join(directory, "Example.dSYM")
            os.mkdir(dsym)
            frames = await self._frames(
                "install_dsym",
                is_local=True,
                dsym=dsym,
                bundle_id="com.example.app",
                compression=Compression.GZIP,
                bundle_type=FileContainerType.APPLICATION,
            )
        self.assertEqual(
            frames,
            ["destination", "link_dsym_to_bundle", "compression:GZIP", "file_path"],
        )

    async def test_a_local_app_with_options(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = os.path.join(directory, "Example.app")
            os.mkdir(app)
            frames = await self._frames(
                "install",
                is_local=True,
                bundle=app,
                make_debuggable=True,
                override_modification_time=True,
            )
        self.assertEqual(
            frames,
            [
                "destination",
                "make_debuggable",
                "override_modification_time",
                "file_path",
            ],
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


class _Clock:
    def __init__(self, *times: float, step: float = 0.0) -> None:
        self._times = list(times)
        self._step = step
        self._now = 0.0

    def __call__(self) -> float:
        if self._times:
            self._now = self._times.pop(0)
        else:
            self._now += self._step
        return self._now


class UploadProgressTests(TestCase):
    def test_reports_the_percentage_of_a_known_total(self) -> None:
        lines: list[str] = []
        progress = UploadProgress(
            report=lines.append,
            total=10 * MIB,
            clock=_Clock(0.0, 1.0, 2.0, 4.0, 10.0, 12.0),
        )
        for size in (1, 1, 2, 6):
            progress.count(size * MIB)
        progress.finish()
        self.assertEqual(
            lines,
            [
                "Uploading: 2.0 MiB sent (20%), 1.0 MiB/s",
                "Uploading: 10.0 MiB sent (100%), 1.0 MiB/s",
                "Uploaded 10.0 MiB in 12s, waiting for the companion to install",
            ],
        )

    def test_reports_bytes_and_rate_without_a_total(self) -> None:
        lines: list[str] = []
        progress = UploadProgress(
            report=lines.append, total=None, clock=_Clock(0.0, 3.0, 4.0)
        )
        progress.count(6 * MIB)
        progress.finish()
        self.assertEqual(
            lines,
            [
                "Uploading: 6.0 MiB sent, 2.0 MiB/s",
                "Uploaded 6.0 MiB in 4s, waiting for the companion to install",
            ],
        )

    def test_an_upload_within_the_delay_reports_nothing(self) -> None:
        lines: list[str] = []
        progress = UploadProgress(
            report=lines.append, total=4 * MIB, clock=_Clock(step=0.5)
        )
        for _ in range(3):
            progress.count(MIB)
        progress.finish()
        self.assertEqual(lines, [])

    def test_a_percentage_never_exceeds_100(self) -> None:
        lines: list[str] = []
        progress = UploadProgress(
            report=lines.append, total=MIB, clock=_Clock(0.0, 2.0)
        )
        progress.count(2 * MIB)
        self.assertEqual(lines, ["Uploading: 2.0 MiB sent (100%), 1.0 MiB/s"])


class RemainingSizeTests(TestCase):
    def test_a_regular_file_reports_the_bytes_after_its_position(self) -> None:
        with tempfile.TemporaryFile() as file:
            file.write(b"x" * 100)
            file.seek(30)
            self.assertEqual(remaining_size(file), 70)

    def test_a_pipe_has_no_size(self) -> None:
        (read_fd, write_fd) = os.pipe()
        with os.fdopen(read_fd, "rb") as reader, os.fdopen(write_fd, "wb"):
            self.assertIsNone(remaining_size(reader))

    def test_an_in_memory_stream_has_no_size(self) -> None:
        self.assertIsNone(remaining_size(io.BytesIO(b"data")))


class InstallUploadProgressTests(TestCase):
    async def _install(
        self, bundle: str, *, is_local: bool, clock: _Clock
    ) -> tuple[list[str], bytes]:
        stream = ScriptedStream(InstallResponse(name="com.example.app"))
        client, _ = make_client("install", stream, is_local=is_local)
        client.companion = dataclasses.replace(
            client.companion,
            supported_compressions=frozenset({Compression.GZIP, Compression.ZSTD}),
            zstd_zip_streams=True,
        )
        lines: list[str] = []
        with (
            patch("idb.common.tar.has_zstd_compressor", return_value=True),
            patch(
                "idb.grpc.client.UploadProgress",
                functools.partial(UploadProgress, clock=clock),
            ),
        ):
            async for _ in client.install(
                bundle=bundle, on_upload_progress=lines.append
            ):
                pass
        sent = b"".join(
            message.payload.data
            for (message, _) in stream.sent
            if isinstance(message, InstallRequest) and message.payload.data
        )
        return (lines, sent)

    async def test_an_ipa_reports_the_bytes_read_against_its_size(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "App.ipa")
            with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_STORED) as ipa:
                ipa.writestr("Payload/App.app/App", b"\0" * (6 * MIB))
            size = os.path.getsize(path)
            (lines, sent) = await self._install(
                path, is_local=False, clock=_Clock(step=3.0)
            )
        self.assertLess(len(sent), MIB, "a stored zip is re-wrapped in zstd")
        self.assertEqual(
            lines,
            [
                f"Uploading: 4.0 MiB sent ({4 * MIB * 100 // size}%), 1.3 MiB/s",
                "Uploaded 6.0 MiB in 9s, waiting for the companion to install",
            ],
        )

    async def test_an_app_reports_the_bytes_sent_without_a_total(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = os.path.join(directory, "App.app")
            os.mkdir(app)
            with open(os.path.join(app, "App"), "wb") as f:
                f.write(os.urandom(1024))
            (lines, sent) = await self._install(
                app, is_local=False, clock=_Clock(step=3.0)
            )
        self.assertGreaterEqual(len(lines), 2, lines)
        for line in lines[:-1]:
            self.assertRegex(line, r"^Uploading: \d+\.\d MiB sent, \d+\.\d MiB/s$")
        self.assertRegex(
            lines[-1],
            rf"^Uploaded {len(sent) / MIB:.1f} MiB in \d+s, waiting for the companion to install$",
        )

    async def test_a_local_companion_reports_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = os.path.join(directory, "App.app")
            os.mkdir(app)
            (lines, sent) = await self._install(
                app, is_local=True, clock=_Clock(step=3.0)
            )
        self.assertEqual((lines, sent), ([], b""))
