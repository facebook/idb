#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from argparse import Namespace
from types import ModuleType
from unittest import mock

from idb.cli import BaseCommand
from idb.common import plugin
from idb.common.types import LoggingMetadata
from idb.utils.testing import TestCase


class _RecordingTelemetryPlugin(ModuleType):
    """Captures the metadata each invocation event is emitted with."""

    def __init__(self) -> None:
        super().__init__("recording_telemetry")
        self.started: list[LoggingMetadata] = []
        self.succeeded: list[LoggingMetadata] = []

    async def before_invocation(self, name: str, metadata: LoggingMetadata) -> None:
        self.started.append(dict(metadata))

    async def after_invocation(
        self, name: str, duration: int, metadata: LoggingMetadata
    ) -> None:
        self.succeeded.append(dict(metadata))


class _NoopCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "does nothing, for metadata assembly tests"

    @property
    def name(self) -> str:
        return "noop"

    async def _run_impl(self, args: Namespace) -> None:
        return None


def _args(**overrides: object) -> Namespace:
    values: dict[str, object] = {
        "log_level": "INFO",
        "log_level_deprecated": None,
        "json": False,
        "reason": None,
    }
    values.update(overrides)
    return Namespace(**values)


class CommandTelemetryMetadataTest(TestCase):
    async def test_command_metadata_carries_no_parsed_arguments_json(self) -> None:
        telemetry = _RecordingTelemetryPlugin()
        args = _args(udid="SIM-1")
        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            await _NoopCommand().run(args)
        self.assertEqual(len(telemetry.succeeded), 1)
        # The command_line normvector carries the canonical CLI arguments;
        # command rows no longer duplicate the parsed Namespace as JSON.
        self.assertNotIn("arguments", telemetry.succeeded[0])

    async def test_command_metadata_carries_truncated_reason(self) -> None:
        telemetry = _RecordingTelemetryPlugin()
        args = _args(reason="x" * 300)
        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            await _NoopCommand().run(args)
        self.assertEqual(len(telemetry.succeeded), 1)
        self.assertEqual(telemetry.succeeded[0].get("reason"), "x" * 200)

    async def test_reason_is_absent_when_not_given(self) -> None:
        telemetry = _RecordingTelemetryPlugin()
        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            await _NoopCommand().run(_args())
        self.assertEqual(len(telemetry.succeeded), 1)
        self.assertNotIn("reason", telemetry.succeeded[0])
