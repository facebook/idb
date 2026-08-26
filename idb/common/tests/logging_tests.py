#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from collections.abc import AsyncIterator
from concurrent.futures import CancelledError
from types import ModuleType
from unittest import mock

from idb.common import plugin
from idb.common.logging import log_call
from idb.common.types import LoggingMetadata
from idb.utils.testing import TestCase


class _TelemetryPlugin(ModuleType):
    """Captures the metadata each invocation event is emitted with, snapshotted
    at emission time so later mutations cannot mask what was logged."""

    def __init__(self, updates_per_call: list[LoggingMetadata | None]) -> None:
        super().__init__("telemetry")
        self.updates_per_call: list[LoggingMetadata | None] = list(updates_per_call)
        self.started: list[LoggingMetadata] = []
        self.succeeded: list[LoggingMetadata] = []
        self.succeeded_durations: list[int] = []
        self.failed: list[LoggingMetadata] = []
        self.observed_results: list[object] = []

    async def before_invocation(self, name: str, metadata: LoggingMetadata) -> None:
        self.started.append(dict(metadata))

    async def after_invocation(
        self, name: str, duration: int, metadata: LoggingMetadata
    ) -> None:
        self.succeeded.append(dict(metadata))
        self.succeeded_durations.append(duration)

    async def failed_invocation(
        self,
        name: str,
        duration: int,
        exception: BaseException,
        metadata: LoggingMetadata,
    ) -> None:
        self.failed.append(dict(metadata))

    def on_invocation_result(
        self, name: str, result: object, metadata: LoggingMetadata
    ) -> LoggingMetadata | None:
        self.observed_results.append(result)
        if self.updates_per_call:
            return self.updates_per_call.pop(0)
        return None


class LogCallResultMetadataTest(TestCase):
    async def test_decorator_duration_preserves_subsecond_precision(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        @log_call(name="fetch")
        async def fetch() -> None:
            return None

        with (
            mock.patch.object(plugin, "PLUGINS", [telemetry]),
            mock.patch(
                "idb.common.logging._monotonic",
                side_effect=[10.25, 10.375],
            ),
        ):
            await fetch()

        self.assertEqual([125], telemetry.succeeded_durations)

    async def test_context_manager_duration_preserves_subsecond_precision(
        self,
    ) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        with (
            mock.patch.object(plugin, "PLUGINS", [telemetry]),
            mock.patch(
                "idb.common.logging._monotonic",
                side_effect=[10.25, 10.375],
            ),
        ):
            async with log_call(name="fetch"):
                pass

        self.assertEqual([125], telemetry.succeeded_durations)

    async def test_object_metadata_is_copied_per_invocation(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        class Caller:
            @property
            def metadata(self) -> LoggingMetadata:
                return plugin.resolve_metadata(logger=mock.MagicMock())

            @log_call(name="fetch", metadata={"grpc_method_name": "fetch"})
            async def fetch(self) -> None:
                return None

        caller = Caller()
        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            with plugin.scoped_invocation_metadata({"capture": "capture-1"}):
                await caller.fetch()
            await caller.fetch()

        self.assertEqual("capture-1", telemetry.succeeded[0].get("capture"))
        self.assertNotIn("capture", telemetry.succeeded[1])
        self.assertEqual("fetch", telemetry.succeeded[0].get("grpc_method_name"))
        self.assertEqual("fetch", telemetry.succeeded[1].get("grpc_method_name"))

    async def test_result_metadata_is_merged_into_success_event(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[{"ax_element_count": "3"}])
        result = object()

        @log_call(name="fetch")
        async def fetch() -> object:
            return result

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            value = await fetch()
        self.assertIs(value, result)
        self.assertEqual(telemetry.observed_results, [result])
        self.assertEqual(len(telemetry.succeeded), 1)
        self.assertEqual(telemetry.succeeded[0].get("ax_element_count"), "3")
        self.assertNotIn("ax_element_count", telemetry.started[0])

    async def test_result_hook_is_not_dispatched_on_failure(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[{"ax_element_count": "3"}])

        @log_call(name="fetch")
        async def fetch() -> object:
            raise RuntimeError("boom")

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            with self.assertRaises(RuntimeError):
                await fetch()
        self.assertEqual(telemetry.observed_results, [])
        self.assertEqual(len(telemetry.failed), 1)
        self.assertNotIn("ax_element_count", telemetry.failed[0])

    async def test_result_metadata_does_not_leak_into_later_invocations(self) -> None:
        # The decorator-level metadata dict is shared across invocations of the
        # same function; result tags must only reach the invocation they
        # describe, so the second call's events carry none when its hook
        # returns nothing.
        telemetry = _TelemetryPlugin(updates_per_call=[{"ax_element_count": "3"}, None])

        @log_call(name="fetch", metadata={"grpc_method_name": "fetch"})
        async def fetch() -> object:
            return object()

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            await fetch()
            await fetch()
        self.assertEqual(len(telemetry.succeeded), 2)
        self.assertEqual(telemetry.succeeded[0].get("ax_element_count"), "3")
        self.assertNotIn("ax_element_count", telemetry.started[1])
        self.assertNotIn("ax_element_count", telemetry.succeeded[1])
        self.assertEqual(telemetry.succeeded[1].get("grpc_method_name"), "fetch")


class LogCallEventIdentityTest(TestCase):
    async def test_invocation_metadata_carries_a_per_invocation_event_uuid(
        self,
    ) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        @log_call(name="fetch")
        async def fetch() -> None:
            return None

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            await fetch()
        self.assertNotIn("event_uuid", telemetry.started[0])
        self.assertNotIn("event_uuid", telemetry.succeeded[0])


class LogCallCancellationTest(TestCase):
    """A cancelled invocation must still reach the terminal telemetry hook:
    it dispatches a success-typed event carrying the cancelled flag, from
    both the coroutine and the async-generator wrappers."""

    async def test_cancelled_invocation_emits_terminal_success_event(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        @log_call(name="record")
        async def record() -> None:
            raise CancelledError()

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            with self.assertRaises(CancelledError):
                await record()
        self.assertEqual(len(telemetry.started), 1)
        self.assertEqual(len(telemetry.failed), 0)
        self.assertEqual(len(telemetry.succeeded), 1)
        self.assertEqual(telemetry.succeeded[0].get("cancelled"), True)

    async def test_cancelled_generator_emits_terminal_success_event(self) -> None:
        telemetry = _TelemetryPlugin(updates_per_call=[])

        @log_call(name="stream")
        async def stream() -> AsyncIterator[int]:
            yield 1
            raise CancelledError()

        with mock.patch.object(plugin, "PLUGINS", [telemetry]):
            with self.assertRaises(CancelledError):
                async for _ in stream():
                    pass
        self.assertEqual(len(telemetry.started), 1)
        self.assertEqual(len(telemetry.failed), 0)
        self.assertEqual(len(telemetry.succeeded), 1)
        self.assertEqual(telemetry.succeeded[0].get("cancelled"), True)
