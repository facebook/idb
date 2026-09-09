# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Which simulator the harness around the suite picks.

Pure selection over a listing, so unlike the rest of the suite these run
anywhere.
"""

from __future__ import annotations

import unittest
from typing import Any

from .newest_simulator import newest_iphone, newest_runtime, NoSimulatorError


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


if __name__ == "__main__":
    unittest.main()
