# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from .test_plan import main, TestPlan, TestTarget

PLAN = {
    "schemes": {
        "FBControlCore": ["FBControlCoreTests"],
        "FBControlCoreTests": ["FBControlCoreTests"],
        "FBSimulatorControl": [
            "FBSimulatorControlSmokeTests",
            "FBSimulatorControlUnitTests",
        ],
        "FBSimulatorControlSmokeTests": ["FBSimulatorControlSmokeTests"],
        "FBSimulatorControlUnitTests": ["FBSimulatorControlUnitTests"],
    },
    "testTargets": {
        "FBControlCoreTests": {
            "bootedSimulator": False,
            "prerequisites": [],
            "runner": "standard",
        },
        "FBSimulatorControlSmokeTests": {
            "bootedSimulator": True,
            "prerequisites": ["fbsimulatorcontrol_resources"],
            "runner": "large",
        },
        "FBSimulatorControlUnitTests": {
            "bootedSimulator": False,
            "prerequisites": ["fbsimulatorcontrol_resources", "fixtures"],
            "runner": "standard",
        },
    },
}


class TestPlanTest(unittest.TestCase):
    def setUp(self) -> None:
        directory = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.path = directory / "TestPlan.json"
        self.path.write_text(json.dumps(PLAN))

    def _run(self, *arguments: str) -> tuple[int, str]:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = main(["--plan", str(self.path), *arguments])
        return status, output.getvalue()

    def test_a_scheme_needs_every_step_any_of_its_bundles_does_once(self) -> None:
        plan = TestPlan.load(self.path)
        self.assertEqual(
            plan.prerequisites("FBSimulatorControl"),
            ["fbsimulatorcontrol_resources", "fixtures"],
        )
        self.assertEqual(
            plan.prerequisites("FBSimulatorControlSmokeTests"),
            ["fbsimulatorcontrol_resources"],
        )
        self.assertEqual(plan.prerequisites("FBControlCore"), [])

    def test_the_matrix_has_one_job_per_test_target(self) -> None:
        status, output = self._run("matrix")
        self.assertEqual(status, 0)
        self.assertTrue(output.startswith("targets="))
        self.assertEqual(
            json.loads(output.removeprefix("targets=")),
            [
                {
                    "name": "FBControlCore",
                    "target": "FBControlCoreTests",
                    "bootedSimulator": False,
                    "runsOn": "macos-26",
                },
                {
                    "name": "FBSimulatorControl Smoke",
                    "target": "FBSimulatorControlSmokeTests",
                    "bootedSimulator": True,
                    "runsOn": "macos-26-xlarge",
                },
                {
                    "name": "FBSimulatorControl Unit",
                    "target": "FBSimulatorControlUnitTests",
                    "bootedSimulator": False,
                    "runsOn": "macos-26",
                },
            ],
        )

    def test_a_test_target_no_framework_prefixes_is_named_for_itself(self) -> None:
        plan = TestPlan(
            schemes={"SimulatorIPCTests": ("SimulatorIPCTests",)},
            test_targets={
                "SimulatorIPCTests": TestTarget(
                    "SimulatorIPCTests", False, (), "standard"
                )
            },
        )
        self.assertEqual(plan.display_name("SimulatorIPCTests"), "SimulatorIPC")

    def test_lists_schemes_and_test_targets_one_per_line(self) -> None:
        self.assertEqual(self._run("schemes")[1].split(), sorted(PLAN["schemes"]))
        self.assertEqual(
            self._run("test-targets")[1].split(), sorted(PLAN["testTargets"])
        )

    def test_lists_a_schemes_prerequisites_one_per_line(self) -> None:
        self.assertEqual(
            self._run("prerequisites", "FBSimulatorControl")[1].split(),
            ["fbsimulatorcontrol_resources", "fixtures"],
        )
        self.assertEqual(self._run("prerequisites", "FBControlCore"), (0, "\n"))
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            self._run("prerequisites", "Unknown")
