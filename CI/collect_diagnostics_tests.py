# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test diagnostic selection and collection with temporary files and fake commands."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from .collect_diagnostics import (
    Capture,
    collect,
    Copy,
    diagnostic_plan,
    SIMULATOR_LOG_WINDOW,
)

UDID = "1E4D2A00-0000-4000-8000-000000000000"


class Recorder:
    """Record each command and return its arguments as output."""

    def __init__(self) -> None:
        self.commands: list[list[str]] = []

    def __call__(self, argv):
        self.commands.append(list(argv))
        return " ".join(argv)


def write(path: Path, text: str = "") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return path


class DiagnosticPlanTests(unittest.TestCase):
    def plan(self, **overrides):
        arguments = {
            "home": Path("/home/runner"),
            "companion_root": Path("/tmp"),
            "device_set": Path("/sets/end-to-end"),
            "udid": UDID,
        }
        arguments.update(overrides)
        return diagnostic_plan(**arguments)

    def test_includes_companion_log_and_host_crash_reports(self) -> None:
        patterns = [
            source.pattern for source in self.plan() if isinstance(source, Copy)
        ]
        self.assertIn("/tmp/idb-e2e-*/companion.log", patterns)
        self.assertIn(
            "/home/runner/Library/Logs/DiagnosticReports/idb_companion*.ips", patterns
        )
        self.assertIn(
            "/home/runner/Library/Logs/DiagnosticReports/SimulatorFrameworkBridge*.ips",
            patterns,
        )

    def test_includes_simulator_crash_reports(self) -> None:
        patterns = [
            source.pattern for source in self.plan() if isinstance(source, Copy)
        ]
        self.assertIn(
            f"/sets/end-to-end/{UDID}/data/Library/Logs/CrashReporter/*.ips", patterns
        )

    def test_device_listing_uses_requested_device_set(
        self,
    ) -> None:
        captures = {
            source.name: list(source.argv)
            for source in self.plan()
            if isinstance(source, Capture)
        }
        self.assertEqual(
            captures["devices.txt"],
            ["xcrun", "simctl", "--set", "/sets/end-to-end", "list", "devices"],
        )

    def test_simulator_log_uses_configured_time_window(self) -> None:
        captures = {
            source.name: list(source.argv)
            for source in self.plan()
            if isinstance(source, Capture)
        }
        self.assertEqual(
            captures["simulator-log.txt"],
            [
                "xcrun",
                "simctl",
                "--set",
                "/sets/end-to-end",
                "spawn",
                UDID,
                "log",
                "show",
                "--last",
                SIMULATOR_LOG_WINDOW,
                "--style",
                "compact",
            ],
        )

    def test_missing_simulator_keeps_host_diagnostics(self) -> None:
        for absent in ({"device_set": None}, {"udid": None}, {"udid": ""}):
            with self.subTest(**absent):
                plan = self.plan(**absent)
                self.assertEqual(len(plan), 3)
                self.assertTrue(all(isinstance(source, Copy) for source in plan))


class CollectTests(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.root))
        self.output = self.root / "diagnostics"
        self.run = Recorder()

    def test_copies_matching_files(self) -> None:
        write(self.root / "idb-e2e-a" / "companion.log", "first")
        write(self.root / "idb-e2e-b" / "companion.log", "second")
        collected = collect(
            [Copy(str(self.root / "idb-e2e-*" / "companion.log"))],
            self.output,
            self.run,
        )
        # Files with the same basename currently overwrite each other.
        self.assertEqual(collected, ["companion.log", "companion.log"])
        self.assertTrue((self.output / "companion.log").exists())

    def test_unmatched_pattern_collects_no_files(self) -> None:
        self.assertEqual(
            collect([Copy(str(self.root / "absent" / "*.ips"))], self.output, self.run),
            [],
        )
        self.assertTrue(self.output.is_dir())

    def test_saves_command_output(self) -> None:
        collected = collect(
            [Capture("devices.txt", ("xcrun", "simctl", "list"))], self.output, self.run
        )
        self.assertEqual(collected, ["devices.txt"])
        self.assertEqual((self.output / "devices.txt").read_text(), "xcrun simctl list")
        self.assertEqual(self.run.commands, [["xcrun", "simctl", "list"]])

    def test_collection_continues_after_source_error(self) -> None:
        def raising(argv):
            raise OSError("xcrun is not on this host")

        collected = collect(
            [
                Capture("devices.txt", ("xcrun", "simctl", "list")),
                Copy(str(write(self.root / "crash.ips"))),
            ],
            self.output,
            raising,
        )
        self.assertEqual(collected, ["crash.ips"])
