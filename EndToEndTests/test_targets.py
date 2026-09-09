# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The companion describes the simulator it was started for."""

from __future__ import annotations

from .harness import IdbEndToEndTestCase


class TargetTests(IdbEndToEndTestCase):
    async def test_describe_reports_the_provided_simulator(self) -> None:
        description = await self.idb_json("describe")

        self.assertEqual(description["udid"], self.udid)
        self.assertEqual(description["target_type"], "simulator")
        self.assertEqual(description["state"], "Booted")
        self.assertTrue(
            description["os_version"], "describe should report an OS version"
        )
        self.assertTrue(description["name"], "describe should report the device name")

        dimensions = description["screen_dimensions"]
        self.assertIsNotNone(dimensions, "a booted simulator has a screen")
        self.assertGreater(dimensions["width"], 0)
        self.assertGreater(dimensions["height"], 0)

    async def test_describe_agrees_with_simctl_about_the_state(self) -> None:
        self.assertEqual(await self.simctl.state(), "Booted")
        self.assertEqual((await self.idb_json("describe"))["state"], "Booted")
