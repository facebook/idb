#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import os
from unittest import mock

from idb.common.agent import agent_metadata, is_agent, parse_agent_metadata
from idb.utils.testing import TestCase


class AgentMetadataTest(TestCase):
    def test_parses_key_value_pairs(self) -> None:
        self.assertEqual(
            parse_agent_metadata("id=claude_code,session_id=sess-1"),
            {"id": "claude_code", "session_id": "sess-1"},
        )

    def test_empty_value_is_empty(self) -> None:
        self.assertEqual(parse_agent_metadata(""), {})

    def test_entries_without_key_or_value_are_dropped(self) -> None:
        self.assertEqual(
            parse_agent_metadata("id=codex,garbage,=orphan,empty="),
            {"id": "codex"},
        )

    def test_agent_metadata_reads_environment(self) -> None:
        env = {"CODING_AGENT_METADATA": "id=codex"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent_metadata(), {"id": "codex"})
            self.assertTrue(is_agent())

    def test_unset_environment_is_not_an_agent(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(agent_metadata(), {})
            self.assertFalse(is_agent())
