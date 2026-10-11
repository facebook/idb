# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import json
import unittest

from .floor import failures


def _line(source: str, seconds: float, failure: str | None = None) -> str:
    return json.dumps(
        {
            "benchCase": {
                "source": source,
                "format": "tar-gz",
                "shape": {"megabytes": 400, "files": 10},
                "contents": "incompressible",
            },
            "wallSeconds": seconds,
            "failure": failure,
        }
    )


class FloorTest(unittest.TestCase):
    def test_a_case_above_the_floor_passes(self) -> None:
        self.assertEqual(
            failures([_line("url", 1.0), _line("url", 2.0), _line("url", 3.0)]), []
        )

    def test_a_case_whose_median_is_under_the_floor_fails(self) -> None:
        problems = failures([_line("url", 30.0), _line("url", 40.0), _line("url", 1.0)])
        self.assertEqual(len(problems), 1)
        self.assertIn("url tar-gz 400x10 incompressible: 13 MB/s", problems[0])

    def test_a_failed_run_fails_the_check(self) -> None:
        problems = failures(
            [_line("pipe", 1.0), _line("pipe", 1.0, failure="extraction failed")]
        )
        self.assertEqual(problems, ["pipe tar-gz 400x10 incompressible: 1 failed runs"])


if __name__ == "__main__":
    unittest.main()
