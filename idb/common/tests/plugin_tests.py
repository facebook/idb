#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import logging
from argparse import Namespace
from types import ModuleType
from unittest import mock

from idb.common import plugin
from idb.common.command import Command
from idb.common.types import IdbException, LoggingMetadata
from idb.utils.testing import TestCase


class _RecordingPlugin(ModuleType):
    def __init__(self) -> None:
        super().__init__("recording")
        self.command: Command | None = None
        self.args: Namespace | None = None

    def on_command_parsed(
        self, logger: logging.Logger, command: Command, args: Namespace
    ) -> None:
        self.command = command
        self.args = args


class _FailingPlugin(ModuleType):
    def on_command_parsed(
        self, logger: logging.Logger, command: Command, args: Namespace
    ) -> None:
        raise RuntimeError("plugin failure")


class _RejectingPlugin(ModuleType):
    def on_command_parsed(
        self, logger: logging.Logger, command: Command, args: Namespace
    ) -> None:
        raise IdbException("rejected by policy")


class _ResultObservingPlugin(ModuleType):
    def __init__(self, name: str, updates: LoggingMetadata | None) -> None:
        super().__init__(name)
        self.updates = updates
        self.observed_name: str | None = None
        self.observed_result: object | None = None
        self.observed_metadata: LoggingMetadata | None = None

    def on_invocation_result(
        self, name: str, result: object, metadata: LoggingMetadata
    ) -> LoggingMetadata | None:
        self.observed_name = name
        self.observed_result = result
        self.observed_metadata = metadata
        return self.updates


class _FailingResultPlugin(ModuleType):
    def on_invocation_result(
        self, name: str, result: object, metadata: LoggingMetadata
    ) -> LoggingMetadata:
        raise RuntimeError("plugin failure")


class _InstructingPlugin(ModuleType):
    def __init__(self, name: str, section: str) -> None:
        super().__init__(name)
        self.section = section
        self.names: list[str] | None = None

    def get_agent_instructions(self, names: list[str]) -> str:
        self.names = list(names)
        return self.section


class _FailingInstructionsPlugin(ModuleType):
    def get_agent_instructions(self, names: list[str]) -> str:
        raise RuntimeError("instructions failure")


class GetAgentInstructionsTest(TestCase):
    def test_contributions_join_in_plugin_order(self) -> None:
        first = _InstructingPlugin("first", "first section")
        second = _InstructingPlugin("second", "second section")
        with mock.patch.object(plugin, "PLUGINS", [first, second]):
            joined = plugin.get_agent_instructions(names=["agent"])
        self.assertEqual(joined, "first section\nsecond section")
        self.assertEqual(first.names, ["agent"])
        self.assertEqual(second.names, ["agent"])

    def test_plugin_failure_is_swallowed_and_later_plugins_contribute(self) -> None:
        failing = _FailingInstructionsPlugin("failing")
        contributing = _InstructingPlugin("contributing", "still here")
        with mock.patch.object(plugin, "PLUGINS", [failing, contributing]):
            self.assertEqual(
                plugin.get_agent_instructions(names=["agent"]), "still here"
            )

    def test_empty_contributions_are_skipped(self) -> None:
        silent = _InstructingPlugin("silent", "")
        with mock.patch.object(plugin, "PLUGINS", [silent]):
            self.assertEqual(plugin.get_agent_instructions(names=["agent"]), "")

    def test_no_plugins_yield_empty_instructions(self) -> None:
        with mock.patch.object(plugin, "PLUGINS", []):
            self.assertEqual(plugin.get_agent_instructions(names=["agent"]), "")


class PluginDispatchTest(TestCase):
    def test_rejection_propagates(self) -> None:
        rejecting = _RejectingPlugin("rejecting")
        with mock.patch.object(plugin, "PLUGINS", [rejecting]):
            with self.assertRaises(IdbException):
                plugin.on_command_parsed(
                    logger=logging.getLogger("test"),
                    command=mock.MagicMock(spec=Command),
                    args=Namespace(),
                )

    def test_rejection_short_circuits_later_plugins(self) -> None:
        rejecting = _RejectingPlugin("rejecting")
        recording = _RecordingPlugin()
        with mock.patch.object(plugin, "PLUGINS", [rejecting, recording]):
            with self.assertRaises(IdbException):
                plugin.on_command_parsed(
                    logger=logging.getLogger("test"),
                    command=mock.MagicMock(spec=Command),
                    args=Namespace(),
                )
        self.assertIsNone(recording.command)

    def test_plugin_failure_is_swallowed_and_later_plugins_run(self) -> None:
        failing = _FailingPlugin("failing")
        recording = _RecordingPlugin()
        command = mock.MagicMock(spec=Command)
        args = Namespace()
        test_logger = logging.getLogger("test")
        with (
            mock.patch.object(plugin, "PLUGINS", [failing, recording]),
            mock.patch.object(test_logger, "exception") as log_exception,
        ):
            plugin.on_command_parsed(logger=test_logger, command=command, args=args)
        self.assertIs(recording.command, command)
        self.assertIs(recording.args, args)
        log_exception.assert_called_once()


class OnInvocationResultTest(TestCase):
    def test_invocation_context_is_forwarded_to_plugins(self) -> None:
        observing = _ResultObservingPlugin("observing", updates=None)
        result = object()
        metadata: LoggingMetadata = {"grpc_method_name": "accessibility_info"}
        with mock.patch.object(plugin, "PLUGINS", [observing]):
            plugin.on_invocation_result(
                name="accessibility_info", result=result, metadata=metadata
            )
        self.assertEqual(observing.observed_name, "accessibility_info")
        self.assertIs(observing.observed_result, result)
        self.assertIs(observing.observed_metadata, metadata)

    def test_updates_from_plugins_are_merged_with_later_plugins_winning(self) -> None:
        first = _ResultObservingPlugin("first", updates={"col": "1", "only": "first"})
        second = _ResultObservingPlugin("second", updates={"col": "2"})
        with mock.patch.object(plugin, "PLUGINS", [first, second]):
            updates = plugin.on_invocation_result(
                name="invocation", result=object(), metadata={}
            )
        self.assertEqual(updates, {"col": "2", "only": "first"})

    def test_plugin_returning_none_contributes_nothing(self) -> None:
        observing = _ResultObservingPlugin("observing", updates=None)
        with mock.patch.object(plugin, "PLUGINS", [observing]):
            updates = plugin.on_invocation_result(
                name="invocation", result=object(), metadata={}
            )
        self.assertEqual(updates, {})

    def test_plugin_without_hook_is_skipped(self) -> None:
        with mock.patch.object(plugin, "PLUGINS", [_RecordingPlugin()]):
            updates = plugin.on_invocation_result(
                name="invocation", result=object(), metadata={}
            )
        self.assertEqual(updates, {})

    def test_plugin_failure_is_swallowed_and_later_plugins_run(self) -> None:
        failing = _FailingResultPlugin("failing")
        observing = _ResultObservingPlugin("observing", updates={"col": "value"})
        with (
            mock.patch.object(plugin, "PLUGINS", [failing, observing]),
            mock.patch.object(plugin.logger, "exception") as log_exception,
        ):
            updates = plugin.on_invocation_result(
                name="invocation", result=object(), metadata={}
            )
        self.assertEqual(updates, {"col": "value"})
        log_exception.assert_called_once()
