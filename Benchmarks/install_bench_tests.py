# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import argparse
import asyncio
import os
import stat
import subprocess
import tempfile
import time
import unittest
import unittest.mock
import zipfile
from pathlib import Path

from .install_bench import (
    Companion,
    completion_columns,
    csv,
    exclusive,
    http_server,
    install_argv,
    Link,
    pad_bundle,
    PATTERNS,
    percentile,
    positive_int,
    rss_kb,
    RSSSampler,
    ShapedProxy,
    tree_bytes,
    write_ipa,
)


class ShapedProxyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        async def echo(
            reader: asyncio.StreamReader, writer: asyncio.StreamWriter
        ) -> None:
            while data := await reader.read(65536):
                writer.write(data)
                await writer.drain()
            writer.close()

        self.upstream = await asyncio.start_server(echo, "127.0.0.1", 0)
        self.upstream_port = self.upstream.sockets[0].getsockname()[1]

    async def asyncTearDown(self) -> None:
        self.upstream.close()
        await self.upstream.wait_closed()

    async def round_trip(self, link: Link, payload: bytes) -> float:
        proxy = ShapedProxy(link, self.upstream_port)
        port = await proxy.start()
        try:
            reader, writer = await asyncio.open_connection("127.0.0.1", port)
            start = time.monotonic()

            async def send() -> None:
                writer.write(payload)
                await writer.drain()
                writer.write_eof()

            sender = asyncio.create_task(send())
            received = await reader.read(-1)
            elapsed = time.monotonic() - start
            await sender
            writer.close()
            self.assertEqual(received, payload)
            return elapsed
        finally:
            await proxy.stop()

    async def test_adds_the_round_trip_time(self) -> None:
        elapsed = await self.round_trip(Link("t", 200, None, None), b"ping")
        self.assertGreaterEqual(elapsed, 0.2)
        self.assertLess(elapsed, 0.35)

    async def test_caps_bandwidth(self) -> None:
        # 2 MB at 40 Mbit/s (5 MB/s) is 0.4s each way, pipelined through the echo.
        elapsed = await self.round_trip(Link("t", 0, 40, None), os.urandom(2_000_000))
        self.assertGreaterEqual(elapsed, 0.4)
        self.assertLess(elapsed, 0.7)

    async def test_window_bounds_throughput_to_window_per_round_trip(self) -> None:
        # 256 KiB per 100ms round trip: 1 MiB needs four windows.
        elapsed = await self.round_trip(
            Link("t", 100, None, 256), os.urandom(1024 * 1024)
        )
        self.assertGreaterEqual(elapsed, 0.4)
        self.assertLess(elapsed, 0.7)


class FixtureTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        self.app = self.directory / "Bench.app"
        self.app.mkdir()
        (self.app / "Bench").write_bytes(b"binary")
        (self.app / "Bench").chmod(0o755)
        (self.app / "Info.plist").write_bytes(b"plist")
        (self.app / "Link").symlink_to("Info.plist")

    def test_padding_reaches_the_size_in_files_of_the_given_size(self) -> None:
        pad_bundle(self.app, 1024 * 1024, 64, 0.5)
        padding = [p for p in (self.app / "BenchPadding").rglob("*") if p.is_file()]
        self.assertEqual(len(padding), 16)
        self.assertEqual(tree_bytes(self.app / "BenchPadding"), 1024 * 1024)

    def test_ipa_has_payload_layout_with_modes_and_symlinks(self) -> None:
        ipa = self.directory / "Bench.ipa"
        write_ipa(self.app, ipa, zipfile.ZIP_STORED)
        with zipfile.ZipFile(ipa) as archive:
            entries = {info.filename: info for info in archive.infolist()}
            self.assertIn("Payload/Bench.app/", entries)
            binary = entries["Payload/Bench.app/Bench"]
            self.assertTrue(stat.S_IXUSR & (binary.external_attr >> 16))
            link = entries["Payload/Bench.app/Link"]
            self.assertTrue(stat.S_ISLNK(link.external_attr >> 16))
            self.assertEqual(archive.read(link), b"Info.plist")


class CurlRouteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        (self.directory / "stored.ipa").write_bytes(b"ipa bytes")
        # Stands in for the client: records its arguments and what it reads from stdin.
        self.idb = self.directory / "idb"
        self.idb.write_text('#!/bin/sh\necho "$@" > "$0.args"\ncat > "$0.stdin"\n')
        self.idb.chmod(0o755)

    def run_curl(self, path: str) -> int:
        with http_server(self.directory) as port:
            argv = install_argv(
                PATTERNS["curl-tgz"],
                self.idb,
                1234,
                f"http://127.0.0.1:{port}/{path}",
                [],
            )
            return subprocess.run(argv, capture_output=True).returncode

    def test_pipes_the_download_to_the_client_reading_stdin(self) -> None:
        self.assertEqual(self.run_curl("stored.ipa"), 0)
        self.assertEqual(Path(f"{self.idb}.stdin").read_bytes(), b"ipa bytes")
        self.assertEqual(
            Path(f"{self.idb}.args").read_text().split(),
            ["--companion", "127.0.0.1:1234", "--compression", "GZIP"]
            + ["install", "--json", "-"],
        )

    def test_a_failed_download_fails_the_install(self) -> None:
        self.assertNotEqual(self.run_curl("missing.ipa"), 0)


class CompanionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())
        # Stands in for the companion: records its arguments and reports readiness.
        self.companion = self.directory / "companion"
        self.companion.write_text(
            '#!/bin/sh\necho "$@" > "$0.args"\necho \'{"grpc_port": 43210}\'\nexec sleep 60\n'
        )
        self.companion.chmod(0o755)

    def test_serves_on_the_port_the_companion_reports(self) -> None:
        companion = Companion(self.companion, "UDID", None, self.directory)
        try:
            args = Path(f"{self.companion}.args").read_text().split()
            requested = args[args.index("--grpc-port") + 1]
            self.assertEqual(requested, "0")
            self.assertEqual(companion.port, 43210)
        finally:
            companion.stop()


class RSSTests(unittest.TestCase):
    def test_reads_a_running_process_and_nothing_once_it_has_gone(self) -> None:
        if rss_kb(os.getpid()) is None:
            self.skipTest("ps can't be run here")
        self.assertGreater(rss_kb(os.getpid()) or 0, 0)
        gone = subprocess.Popen(["true"])
        gone.wait()
        self.assertIsNone(rss_kb(gone.pid))

    def test_a_sampler_keeps_the_highest_reading(self) -> None:
        if rss_kb(os.getpid()) is None:
            self.skipTest("ps can't be run here")
        sampler = RSSSampler(os.getpid())
        sampler.start()
        ballast = bytearray(64 << 20)
        ballast[::4096] = b"x" * len(ballast[::4096])
        time.sleep(0.2)
        sampler.stop()
        self.assertGreater(sampler.peak_kb or 0, 64 << 10)

    def test_a_process_reads_as_nothing_where_ps_is_forbidden(self) -> None:
        with unittest.mock.patch.object(
            subprocess, "run", side_effect=PermissionError("ps")
        ):
            self.assertIsNone(rss_kb(os.getpid()))

    def test_a_sampler_that_never_reads_reports_no_peak(self) -> None:
        gone = subprocess.Popen(["true"])
        gone.wait()
        sampler = RSSSampler(gone.pid)
        sampler.start()
        sampler.stop()
        self.assertIsNone(sampler.peak_kb)


class ExclusiveTests(unittest.TestCase):
    def test_a_second_run_on_the_same_simulator_is_refused(self) -> None:
        # Each test locks its own udid, since the runner runs them in parallel.
        with exclusive(self.id()):
            with self.assertRaisesRegex(SystemExit, "another install bench"):
                with exclusive(self.id()):
                    pass

    def test_the_simulator_is_free_once_a_run_ends(self) -> None:
        with exclusive(self.id()):
            pass
        with exclusive(self.id()):
            pass


class SummaryTests(unittest.TestCase):
    def test_parses_completion_columns(self) -> None:
        line = (
            "2026-09-28 Install com.example succeeded "
            "{size=1048576, receive_ms=12, extract_ms=34, payload_kind=data_zip}"
        )
        self.assertEqual(
            completion_columns(line),
            {
                "size": "1048576",
                "receive_ms": "12",
                "extract_ms": "34",
                "payload_kind": "data_zip",
            },
        )

    def test_lines_without_columns_parse_to_nothing(self) -> None:
        self.assertEqual(completion_columns("Install succeeded"), {})

    def test_percentile_interpolates(self) -> None:
        self.assertEqual(percentile([4.0, 1.0, 3.0, 2.0], 0.5), 2.5)
        self.assertEqual(percentile([5.0], 0.9), 5.0)


class ArgumentTests(unittest.TestCase):
    def test_sizes_must_be_positive(self) -> None:
        # A zero file size would pad the bundle forever.
        self.assertEqual(csv(positive_int)("16,256"), [16, 256])
        for value in ["0", "64,-1"]:
            with (
                self.subTest(value=value),
                self.assertRaises(argparse.ArgumentTypeError),
            ):
                csv(positive_int)(value)
