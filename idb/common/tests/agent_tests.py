#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import os
from unittest import mock

from idb.common.agent import (
    agent_metadata,
    agent_product,
    is_agent,
    parse_agent_metadata,
)
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
            self.assertIsNone(agent_product())
            self.assertFalse(is_agent())


class AgentProductTest(TestCase):
    def test_ai_agent_product_is_the_leading_segment(self) -> None:
        env = {"AI_AGENT": "claude-code/2.4.1/agent"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent_product(), "claude-code")
            self.assertTrue(is_agent())

    def test_ai_agent_outranks_every_other_signal(self) -> None:
        env = {
            "AI_AGENT": "first/1",
            "AGENT": "second",
            "CODING_AGENT_METADATA": "id=third",
            "CLAUDECODE": "1",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent_product(), "first")

    def test_agent_outranks_metadata_and_claudecode(self) -> None:
        env = {
            "AGENT": "second",
            "CODING_AGENT_METADATA": "id=third",
            "CLAUDECODE": "1",
        }
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent_product(), "second")

    def test_metadata_id_outranks_claudecode(self) -> None:
        env = {"CODING_AGENT_METADATA": "id=third", "CLAUDECODE": "1"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(agent_product(), "third")

    def test_claudecode_requires_exactly_one(self) -> None:
        with mock.patch.dict(os.environ, {"CLAUDECODE": "1"}, clear=True):
            self.assertEqual(agent_product(), "claude-code")
        for value in ("0", "true", ""):
            with mock.patch.dict(os.environ, {"CLAUDECODE": value}, clear=True):
                self.assertIsNone(agent_product())
                self.assertFalse(is_agent())

    def test_metadata_without_id_is_not_a_product(self) -> None:
        env = {"CODING_AGENT_METADATA": "session_id=sess-1"}
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertIsNone(agent_product())
            self.assertFalse(is_agent())
