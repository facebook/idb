#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import contextlib
import io

from idb.cli.main import gen_main as cli_main
from idb.utils.testing import TestCase


async def _run(cmd_input: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        exit_code = await cli_main(cmd_input=cmd_input)
    return (int(exit_code or 0), out.getvalue())


class HelpCommandTest(TestCase):
    async def test_bare_help_lists_topics_and_succeeds(self) -> None:
        (exit_code, output) = await _run(["help"])
        self.assertEqual(exit_code, 0)
        self.assertIn("agent", output)
        self.assertIn("idb help <topic>", output)

    async def test_agent_topic_pins_load_bearing_guidance(self) -> None:
        (exit_code, output) = await _run(["help", "agent"])
        self.assertEqual(exit_code, 0)
        self.assertIn("idb ui tap <marker> --match-key AXUniqueId", output)
        self.assertIn("describe-all --json", output)
        self.assertIn("--reason", output)
        self.assertIn("CODING_AGENT_METADATA", output)
        self.assertIn("last resort", output)

    async def test_subtopic_words_join_to_a_key(self) -> None:
        # No subtopics exist yet, so the joined key must miss cleanly and
        # name itself in the error.
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            (exit_code, _) = await _run(["help", "agent", "performance"])
        self.assertEqual(exit_code, 1)
        self.assertIn("No help topic 'agent-performance'", err.getvalue())

    async def test_unknown_topic_fails_and_lists_topics(self) -> None:
        err = io.StringIO()
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            exit_code = await cli_main(cmd_input=["help", "nonsense"])
        self.assertEqual(exit_code, 1)
        self.assertIn("No help topic 'nonsense'", err.getvalue())
        self.assertIn("agent", err.getvalue())

    async def test_help_requires_no_companion_or_target(self) -> None:
        # The command must run to completion with no companion configured;
        # reaching exit 0 with output IS the proof, since any target
        # resolution would fail in this environment.
        (exit_code, output) = await _run(["help", "agent"])
        self.assertEqual(exit_code, 0)
        self.assertTrue(output.startswith("idb agent guide"))
