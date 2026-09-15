# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from .dependency_lock import load_pins, main, prepare_codegen, verify_resolved


def pin(identity: str, version: str = "1.2.3", revision: str = "a" * 40) -> dict:
    return {
        "identity": identity,
        "kind": "remoteSourceControl",
        "location": f"https://github.com/example/{identity}.git",
        "state": {"version": version, "revision": revision},
    }


class DependencyLockTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.expected = self.root / "Package.resolved"
        self.actual = self.root / "Actual.resolved"
        self.entries = [pin("grpc-swift"), pin("swift-protobuf"), pin("swift-log")]
        self.write(self.expected, self.entries)

    def write(self, path: Path, entries: list[dict], **fields) -> None:
        path.write_text(json.dumps({"version": 3, "pins": entries, **fields}) + "\n")

    def test_accepts_equivalent_resolution_despite_format_and_origin(self) -> None:
        self.entries[0]["location"] = "https://github.com/example/grpc-swift/"
        self.write(self.actual, self.entries[::-1], originHash="another manifest")
        self.assertIsNone(verify_resolved(self.expected, self.actual))

    def test_rejects_revision_change_at_same_version(self) -> None:
        self.entries[2]["state"]["revision"] = "b" * 40
        self.write(self.actual, self.entries)
        with self.assertRaisesRegex(ValueError, "swift-log: expected"):
            verify_resolved(self.expected, self.actual)

    def test_rejects_version_drift(self) -> None:
        self.entries[2]["state"]["version"] = "2.0.0"
        self.write(self.actual, self.entries)
        with self.assertRaisesRegex(ValueError, "swift-log: expected"):
            verify_resolved(self.expected, self.actual)

    def test_rejects_another_repository_with_same_identity(self) -> None:
        self.entries[2]["location"] = "https://github.com/another/swift-log.git"
        self.write(self.actual, self.entries)
        with self.assertRaisesRegex(ValueError, "swift-log: expected"):
            verify_resolved(self.expected, self.actual)

    def test_rejects_missing_and_added_dependencies(self) -> None:
        self.write(self.actual, self.entries[:2] + [pin("surprise")])
        with self.assertRaises(ValueError) as error:
            verify_resolved(self.expected, self.actual)
        self.assertIn("swift-log: missing", str(error.exception))
        self.assertIn("surprise: absent", str(error.exception))

    def test_rejects_duplicate_identity(self) -> None:
        self.write(self.expected, self.entries + [pin("swift-log", "9.0.0")])
        with self.assertRaisesRegex(ValueError, "duplicate dependency swift-log"):
            load_pins(self.expected)

    def test_rejects_unpinned_revision(self) -> None:
        self.entries[2]["state"]["revision"] = "main"
        self.write(self.expected, self.entries)
        with self.assertRaisesRegex(ValueError, "swift-log must pin"):
            load_pins(self.expected)

    def test_cli_reports_non_object_lockfiles(self) -> None:
        for document in (None, [], "lockfile", 42, True):
            with self.subTest(document=document):
                self.expected.write_text(json.dumps(document))
                with (
                    patch(
                        "sys.argv",
                        [
                            "dependency_lock.py",
                            "check",
                            str(self.expected),
                            str(self.actual),
                        ],
                    ),
                    self.assertLogs(level="ERROR") as logs,
                ):
                    self.assertEqual(main(), 1)
                self.assertIn(str(self.expected), logs.output[0])
                self.assertIn(
                    "expected a nonempty SwiftPM v2/v3 lockfile", logs.output[0]
                )

    def test_rejects_non_object_pin_state(self) -> None:
        for state in (None, [], "state", 42, True):
            with self.subTest(state=state):
                self.entries[0]["state"] = state
                self.write(self.expected, self.entries)
                with self.assertRaisesRegex(
                    ValueError, "grpc-swift: expected a state object"
                ):
                    load_pins(self.expected)

    def test_codegen_updates_the_manifest_and_lock_after_a_bump(self) -> None:
        destination = self.root / "codegen"
        prepare_codegen(self.expected, destination)
        first = (destination / "Package.swift").read_text()
        self.entries[0]["state"] = {"version": "2.4.6", "revision": "b" * 40}
        self.write(self.expected, self.entries)

        prepare_codegen(self.expected, destination)

        self.assertNotEqual(first, (destination / "Package.swift").read_text())
        self.assertIn('exact: "2.4.6"', (destination / "Package.swift").read_text())
        self.assertEqual(
            self.expected.read_bytes(), (destination / "Package.resolved").read_bytes()
        )

    def test_codegen_rejects_missing_plugin_pin_before_writing(self) -> None:
        self.write(self.expected, self.entries[1:])
        destination = self.root / "codegen"
        with self.assertRaisesRegex(
            ValueError, "missing codegen dependency grpc-swift"
        ):
            prepare_codegen(self.expected, destination)
        self.assertFalse(destination.exists())
