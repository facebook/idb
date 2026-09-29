# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path

try:
    from EndToEndTests.documentation import DOCUMENTED_DEMOS
except ImportError:
    from ..EndToEndTests.documentation import DOCUMENTED_DEMOS

from .end_to_end_shard import main, modules, REMAINDER, SHARDS


class EndToEndShardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = (
            Path(self.enterContext(tempfile.TemporaryDirectory())) / "EndToEndTests"
        )
        self.directory.mkdir()
        for name in (
            "test_accessibility",
            "test_files",
            "test_services",
            "test_system",
            "test_targets",
            "harness",
        ):
            (self.directory / f"{name}.py").touch()

    def test_a_named_shard_runs_its_modules(self) -> None:
        self.assertEqual(
            modules("ui", self.directory),
            ["EndToEndTests.test_accessibility", "EndToEndTests.test_services"],
        )

    def test_the_remainder_runs_every_test_module_no_shard_names(self) -> None:
        self.assertEqual(
            modules(REMAINDER, self.directory),
            ["EndToEndTests.test_files", "EndToEndTests.test_targets"],
        )

    def test_every_documented_demo_runs_in_the_demos_shard(self) -> None:
        for slug, identity in DOCUMENTED_DEMOS.items():
            with self.subTest(slug):
                self.assertIn(identity.split(".")[1], SHARDS["demos"])

    def test_prints_the_modules_for_unittest(self) -> None:
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            main(["system", "--directory", str(self.directory)])
        self.assertEqual(printed.getvalue(), "EndToEndTests.test_system\n")

    def test_rejects_an_unknown_shard(self) -> None:
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            main(["everything"])


if __name__ == "__main__":
    unittest.main()
