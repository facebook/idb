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
            str(source.root / source.pattern)
            for source in self.plan()
            if isinstance(source, Copy)
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
            str(source.root / source.pattern)
            for source in self.plan()
            if isinstance(source, Copy)
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
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.output = self.root / "diagnostics"
        self.run = Recorder()

    def test_companion_log_collision(self) -> None:
        write(self.root / "idb-e2e-a" / "companion.log", "first")
        write(self.root / "idb-e2e-b" / "companion.log", "second")
        collected = collect(
            diagnostic_plan(home=self.root / "home", companion_root=self.root),
            self.output,
            self.run,
        )
        # BUG: both reported paths refer to the second log's contents.
        self.assertEqual(
            [(name, (self.output / name).read_text()) for name in collected],
            [("companion.log", "second"), ("companion.log", "second")],
        )

    def test_host_and_simulator_crash_report_collision(self) -> None:
        home = self.root / "home"
        device_set = self.root / "devices"
        filename = "idb_companion-example.ips"
        write(home / "Library/Logs/DiagnosticReports" / filename, "host crash")
        write(
            device_set / UDID / "data/Library/Logs/CrashReporter" / filename,
            "simulator crash",
        )

        collected = collect(
            diagnostic_plan(
                home=home,
                companion_root=self.root,
                device_set=device_set,
                udid=UDID,
            ),
            self.output,
            self.run,
        )

        # BUG: the simulator report overwrites the host report.
        self.assertEqual(
            [
                (name, (self.output / name).read_text())
                for name in collected
                if name.endswith(".ips")
            ],
            [(filename, "simulator crash"), (filename, "simulator crash")],
        )

    def test_unmatched_pattern_collects_no_files(self) -> None:
        self.assertEqual(
            collect([Copy(self.root / "absent", "*.ips")], self.output, self.run),
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
                Copy(write(self.root / "crash.ips").parent, "crash.ips"),
            ],
            self.output,
            raising,
        )
        self.assertEqual(collected, ["crash.ips"])
