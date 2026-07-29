#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import logging
from argparse import Namespace
from types import ModuleType
from unittest import mock

from idb.common import plugin
from idb.common.command import Command
from idb.common.types import IdbException
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
