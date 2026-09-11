# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test runtime selection and provisioning with recorded simctl responses."""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from typing import Any, Sequence

from .provision_simulator import (
    environment_lines,
    newest_iphone,
    newest_runtime,
    NoSimulatorError,
    provision,
    simctl_argv,
)

UDID = "1E4D2A00-0000-4000-8000-000000000000"


def device_type(name: str) -> dict[str, Any]:
    identifier = "com.apple.CoreSimulator.SimDeviceType." + name.replace(" ", "-")
    return {"name": name, "identifier": identifier, "productFamily": "iPhone"}


def runtime(
    version: str,
    *,
    available: bool = True,
    device_types: list[str] | None = None,
    platform: str = "iOS",
) -> dict[str, Any]:
    return {
        "name": f"{platform} {version}",
        "version": version,
        "isAvailable": available,
        "identifier": f"com.apple.CoreSimulator.SimRuntime.{platform}-"
        + version.replace(".", "-"),
        "supportedDeviceTypes": [device_type(name) for name in device_types or []],
    }


class Recorder:
    """Record simctl commands and return runtime data or a new UDID."""

    def __init__(self, runtimes: list[dict[str, Any]], udid: str = UDID) -> None:
        self.commands: list[list[str]] = []
        self._runtimes = runtimes
        self._udid = udid

    def __call__(self, argv: Sequence[str]) -> str:
        self.commands.append(list(argv))
        if "list" in argv:
            return json.dumps({"runtimes": self._runtimes})
        if "create" in argv:
            return self._udid + "\n"
        return ""


class NewestRuntimeTests(unittest.TestCase):
    def test_picks_the_highest_version(self) -> None:
        chosen = newest_runtime([runtime("18.4"), runtime("26.0"), runtime("17.5")])

        self.assertEqual(chosen["version"], "26.0")

    def test_compares_versions_as_numbers_rather_than_as_text(self) -> None:
        chosen = newest_runtime([runtime("18.10"), runtime("18.9")])

        self.assertEqual(chosen["version"], "18.10")

    def test_ignores_a_runtime_that_is_not_available(self) -> None:
        chosen = newest_runtime([runtime("26.0", available=False), runtime("18.4")])

        self.assertEqual(chosen["version"], "18.4")

    def test_ignores_the_other_platforms(self) -> None:
        chosen = newest_runtime(
            [runtime("26.0", platform="watchOS"), runtime("18.4", platform="iOS")]
        )

        self.assertEqual(chosen["version"], "18.4")

    def test_reports_when_there_is_no_ios_runtime(self) -> None:
        with self.assertRaises(NoSimulatorError):
            newest_runtime([runtime("26.0", platform="tvOS")])


class NewestIPhoneTests(unittest.TestCase):
    def test_picks_the_highest_numbered_model(self) -> None:
        chosen = newest_iphone(
            runtime("26.0", device_types=["iPhone 15", "iPhone 17", "iPhone 16"])
        )

        self.assertEqual(chosen["name"], "iPhone 17")

    def test_prefers_the_base_model_to_its_variants(self) -> None:
        chosen = newest_iphone(
            runtime(
                "26.0",
                device_types=["iPhone 17 Pro", "iPhone 17", "iPhone 17 Pro Max"],
            )
        )

        self.assertEqual(chosen["name"], "iPhone 17")

    def test_ignores_a_model_that_is_not_numbered(self) -> None:
        chosen = newest_iphone(
            runtime("26.0", device_types=["iPhone SE (3rd generation)", "iPhone 16"])
        )

        self.assertEqual(chosen["name"], "iPhone 16")

    def test_reports_when_the_runtime_supports_no_numbered_iphone(self) -> None:
        with self.assertRaises(NoSimulatorError):
            newest_iphone(runtime("26.0", device_types=["iPad Pro 11-inch"]))


class SimctlArgvTests(unittest.TestCase):
    def test_scopes_every_command_to_the_device_set(self) -> None:
        argv = simctl_argv(Path("/tmp/set"), "boot", UDID)

        self.assertEqual(argv, ["xcrun", "simctl", "--set", "/tmp/set", "boot", UDID])

    def test_uses_the_default_set_when_there_is_none(self) -> None:
        argv = simctl_argv(None, "boot", UDID)

        self.assertEqual(argv, ["xcrun", "simctl", "boot", UDID])


class EnvironmentLinesTests(unittest.TestCase):
    def test_names_the_device_set_alongside_the_udid(self) -> None:
        lines = environment_lines(UDID, Path("/tmp/set"))

        self.assertEqual(lines, ["DEVICE_SET_PATH=/tmp/set", f"DEVICE_UDID={UDID}"])

    def test_names_only_the_udid_for_the_default_set(self) -> None:
        lines = environment_lines(UDID, None)

        self.assertEqual(lines, [f"DEVICE_UDID={UDID}"])

    def test_prefixes_every_name(self) -> None:
        lines = environment_lines(UDID, Path("/tmp/set"), "TEST_RUNNER_")

        self.assertEqual(
            lines,
            [
                "TEST_RUNNER_DEVICE_SET_PATH=/tmp/set",
                f"TEST_RUNNER_DEVICE_UDID={UDID}",
            ],
        )


class ProvisionTests(unittest.TestCase):
    def test_creates_boots_and_waits_for_the_boot_to_finish(self) -> None:
        recorder = Recorder([runtime("26.0", device_types=["iPhone 17"])])

        lines = provision(recorder, name="e2e", device_set=Path("/tmp/set"))

        self.assertEqual(
            recorder.commands,
            [
                ["xcrun", "simctl", "list", "--json", "runtimes"],
                [
                    "xcrun",
                    "simctl",
                    "--set",
                    "/tmp/set",
                    "create",
                    "e2e",
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                ],
                ["xcrun", "simctl", "--set", "/tmp/set", "boot", UDID],
                ["xcrun", "simctl", "--set", "/tmp/set", "bootstatus", UDID],
            ],
        )
        self.assertEqual(lines, ["DEVICE_SET_PATH=/tmp/set", f"DEVICE_UDID={UDID}"])

    def test_creates_in_the_default_set_when_given_none(self) -> None:
        recorder = Recorder([runtime("26.0", device_types=["iPhone 17"])])

        provision(recorder, name="smoke")

        self.assertTrue(all("--set" not in command for command in recorder.commands))

    def test_reports_a_create_that_named_no_simulator(self) -> None:
        recorder = Recorder([runtime("26.0", device_types=["iPhone 17"])], udid="")

        with self.assertRaises(NoSimulatorError):
            provision(recorder, name="e2e")

    def test_reports_a_machine_with_no_usable_runtime(self) -> None:
        recorder = Recorder([runtime("26.0", platform="tvOS")])

        with self.assertRaises(NoSimulatorError):
            provision(recorder, name="e2e")


if __name__ == "__main__":
    unittest.main()
