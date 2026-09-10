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
        self.assertTrue(
            description["os_version"], "describe should report an OS version"
        )
        self.assertTrue(description["name"], "describe should report the device name")

        dimensions = description["screen_dimensions"]
        self.assertIsNotNone(dimensions, "a booted simulator has a screen")
        self.assertGreater(dimensions["width"], 0)
        self.assertGreater(dimensions["height"], 0)

        # simctl, not idb, is the ground truth for the state.
        self.assertEqual(description["state"], await self.simctl.state())
        self.assertEqual(description["state"], "Booted")
