# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test failure reporting, process checks and polling without a simulator.

The *_tests.py name excludes this module from e2e unittest discovery, which
uses test*.py. Run it separately with python -m unittest EndToEndTests.harness_tests.
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Awaitable, Callable, NoReturn, Sequence
from unittest import mock

from . import harness, recording as recording_module
from .harness import (
    _optional_binary_from_environment,
    client_argv,
    Companion,
    CompanionDied,
    Completed,
    Deadline,
    HarnessError,
    IDB_SETUP_BIN_ENV,
    IdbEndToEndTestCase,
    IdbProcess,
    NotReady,
    run_with_registered_cleanup,
    running_bundle_ids_from_listing,
    select_tests_for_capability,
    shared_companion,
    Simctl,
    STRICT_ENV,
    suite_capability,
    SUITE_CAPABILITY_ENV,
    suite_supports,
    SuiteCapability,
    wait_for_accessibility,
    wait_until,
)
from .recording import Recording

CONNECTION_REFUSED = (
    "Failed to connect to companion at address DomainSocketAddress("
    "path='/tmp/idb-e2e-4xdxnimi/companion.sock'): [Errno 61] Connection refused"
)
HOST_SERVICE_UNAVAILABLE = (
    "SimLaunchHostService.RequestError: Exit Code 149 is not acceptable"
)

# simctl listapps emits an old-style plist that plutil converts to JSON.
LISTAPPS_PLIST = b'{ "com.apple.Preferences" = { CFBundleName = Settings; }; }'
LISTAPPS_JSON = b'{"com.apple.Preferences": {"CFBundleName": "Settings"}}'
FAILED = Completed(1, b"", b"the simulator is not booted")

# Include a running app, an exited app, and a daemon.
LAUNCHCTL_LISTING = """PID\tStatus\tLabel
81046\t0\tUIKitApplication:com.apple.mobilesafari[e334][rb-legacy]
-\t0\tUIKitApplication:com.apple.Preferences[90ff][rb-legacy]
392\t0\tcom.apple.backboardd
"""

Run = Callable[..., Awaitable[Completed]]


class Failed(Exception):
    """Failure raised by the test case stub."""


class Skipped(Exception):
    """Skip raised by the test case stub."""


class ProcessStub:
    def __init__(self, returncode: int | None) -> None:
        self.returncode = returncode

    def poll(self) -> int | None:
        return self.returncode


def companion(returncode: int | None, log_path: Path | None = None) -> Companion:
    """Construct a Companion with a fake process, without spawning one."""
    made = Companion.__new__(Companion)
    made.process = ProcessStub(returncode)
    made.log_path = log_path if log_path is not None else Path("/nonexistent.log")
    return made


class HarnessCaseStub:
    def __init__(self, companion_returncode: int | None = None) -> None:
        self.companion = companion(companion_returncode)
        self.companion.address = "/tmp/companion.sock"
        self.environment = SimpleNamespace(
            idb_bin=Path("/tmp/idb"),
            idb_args=(),
        )
        self.recording: Recording | None = None
        self._result = unittest.TestResult()

    _stop_suite = IdbEndToEndTestCase._stop_suite

    def fail(self, message: str) -> NoReturn:
        raise Failed(message)

    def skipTest(self, reason: str) -> NoReturn:
        raise Skipped(reason)


def report_for(stderr: str, companion_returncode: int | None = None) -> str:
    return reported_by(HarnessCaseStub(companion_returncode), stderr)


def reported_by(case: HarnessCaseStub, stderr: str) -> str:
    try:
        IdbEndToEndTestCase.fail_or_skip_for(
            case, "describe", Completed(1, b"", stderr.encode())
        )
    except Failed as failed:
        return str(failed)
    raise AssertionError("fail_or_skip_for reported no failure")


class ProcessOutputTests(unittest.IsolatedAsyncioTestCase):
    async def test_empty_stdout_reports_stderr_and_exit_status(self) -> None:
        script = (
            "import os, sys; os.close(1); "
            "sys.stderr.write('x' * 262144); "
            "sys.stderr.write(chr(10) + 'application did not respond' + chr(10)); "
            "sys.exit(7)"
        )
        with self.assertRaises(Failed) as raised:
            async with IdbProcess(
                HarnessCaseStub(), [sys.executable, "-c", script], "ui wait General"
            ) as process:
                await process.read_some(5)

        self.assertIn(
            "closed stdout without writing anything (rc=7)", str(raised.exception)
        )
        self.assertIn("application did not respond", str(raised.exception))

    async def test_successful_exit_without_stdout_is_still_a_failure(self) -> None:
        with self.assertRaises(Failed) as raised:
            async with IdbProcess(
                HarnessCaseStub(), [sys.executable, "-c", "pass"], "ui wait General"
            ) as process:
                await process.read_some(5)

        self.assertIn(
            "closed stdout without writing anything (rc=0)", str(raised.exception)
        )

    async def test_closed_stdout_does_not_wait_forever_for_exit(self) -> None:
        script = "import os, time; os.write(1, b'ready'); os.close(1); time.sleep(60)"
        with self.assertRaises(Failed) as raised:
            async with IdbProcess(
                HarnessCaseStub(), [sys.executable, "-c", script], "ui wait General"
            ) as process:
                self.assertEqual(await process.read_some(5), b"ready")
                await process.read_some(1)

        self.assertIn("closed stdout", str(raised.exception))
        self.assertIn("did not exit within 1s", str(raised.exception))
        self.assertIsNotNone(process.returncode)


class ClientArgumentTests(unittest.TestCase):
    def test_places_backend_arguments_before_the_direct_companion(self) -> None:
        argv = client_argv(
            Path("/tmp/idb-rust"),
            ("--no-prune-dead-companion",),
            "/tmp/companion.sock",
            "describe",
            "--json",
        )

        self.assertEqual(
            argv,
            [
                "/tmp/idb-rust",
                "--no-prune-dead-companion",
                "--companion",
                "/tmp/companion.sock",
                "describe",
                "--json",
            ],
        )

    def test_uses_no_backend_arguments_by_default(self) -> None:
        argv = client_argv(Path("/tmp/idb"), (), "/tmp/companion.sock", "describe")

        self.assertEqual(
            argv,
            ["/tmp/idb", "--companion", "/tmp/companion.sock", "describe"],
        )

    @mock.patch.dict(os.environ, {}, clear=True)
    def test_uses_the_client_under_test_for_setup_by_default(self) -> None:
        client = Path("/tmp/idb")

        self.assertEqual(
            _optional_binary_from_environment(IDB_SETUP_BIN_ENV, client), client
        )

    def test_accepts_a_separate_fixture_setup_client(self) -> None:
        with tempfile.NamedTemporaryFile() as executable:
            os.chmod(executable.name, 0o755)
            with mock.patch.dict(
                os.environ, {IDB_SETUP_BIN_ENV: executable.name}, clear=True
            ):
                selected = _optional_binary_from_environment(
                    IDB_SETUP_BIN_ENV, Path("/tmp/idb-rust")
                )

        self.assertEqual(selected, Path(executable.name))


class _SettingsCleanupSuite(unittest.IsolatedAsyncioTestCase):
    events: list[str] = []
    launch_error: BaseException = HarnessError("launch failed")

    async def asyncSetUp(self) -> None:
        async def terminate_settings() -> None:
            self.events.append("terminate Settings")

        async def launch_settings() -> None:
            self.events.append("launch Settings")
            raise self.launch_error

        await run_with_registered_cleanup(
            self.addAsyncCleanup,
            terminate_settings,
            launch_settings,
        )

    async def case_body(self) -> None:
        self.events.append("test body")


class SettingsCleanupTests(unittest.TestCase):
    def run_setup_error(self, error: BaseException) -> unittest.TestResult:
        _SettingsCleanupSuite.events = []
        _SettingsCleanupSuite.launch_error = error
        result = unittest.TestResult()

        _SettingsCleanupSuite("case_body").run(result)

        self.assertEqual(
            _SettingsCleanupSuite.events,
            ["launch Settings", "terminate Settings"],
        )
        self.assertEqual(len(result.errors), 1)
        return result

    def test_settings_cleanup_runs_when_launch_fails(self) -> None:
        result = self.run_setup_error(HarnessError("launch failed"))

        self.assertIn("launch failed", result.errors[0][1])

    def test_settings_cleanup_runs_when_launch_is_cancelled(self) -> None:
        result = self.run_setup_error(asyncio.CancelledError())

        self.assertIn("CancelledError", result.errors[0][1])


class SuiteCapabilityTests(unittest.TestCase):
    READ_TESTS = [
        "test_ui_describe_all_accepts_keys_profiling_and_frame_coverage",
        "test_ui_describe_all_over_both_backends",
        "test_ui_describe_resolves_a_point_and_a_marker",
    ]
    INTERACTION_TESTS = [
        *READ_TESTS,
        "test_ui_scroll_moves_settings_rows_down_and_up",
        "test_ui_tap_opens_general_by_marker",
        "test_ui_tap_opens_general_by_point",
    ]
    REQUIREMENTS = {
        "test_ui_describe_all_accepts_keys_profiling_and_frame_coverage": (
            SuiteCapability.ACCESSIBILITY_READ
        ),
        "test_ui_describe_all_over_both_backends": SuiteCapability.ACCESSIBILITY_READ,
        "test_ui_describe_resolves_a_point_and_a_marker": (
            SuiteCapability.ACCESSIBILITY_READ
        ),
        "test_ui_scroll_moves_settings_rows_down_and_up": (
            SuiteCapability.ACCESSIBILITY_INTERACTION
        ),
        "test_ui_tap_opens_general_by_marker": (
            SuiteCapability.ACCESSIBILITY_INTERACTION
        ),
        "test_ui_tap_opens_general_by_point": (
            SuiteCapability.ACCESSIBILITY_INTERACTION
        ),
    }

    def selected(self) -> tuple[unittest.TestSuite, unittest.TestSuite]:
        suite_type = type(
            "_SuiteCapabilityFixture",
            (unittest.TestCase,),
            {name: lambda _self: None for name in self.INTERACTION_TESTS},
        )
        loader = unittest.TestLoader()
        discovered = loader.loadTestsFromTestCase(suite_type)
        selected = select_tests_for_capability(
            loader,
            discovered,
            suite_type,
            self.REQUIREMENTS,
        )
        return discovered, selected

    @staticmethod
    def names(suite: unittest.TestSuite) -> list[str]:
        return [test._testMethodName for test in suite]

    @mock.patch.dict(os.environ, {}, clear=True)
    def test_unset_capability_defaults_to_interaction(self) -> None:
        discovered, selected = self.selected()

        self.assertIs(
            suite_capability(),
            SuiteCapability.ACCESSIBILITY_INTERACTION,
        )
        self.assertIs(selected, discovered)
        self.assertEqual(self.names(selected), self.INTERACTION_TESTS)

    def test_each_explicit_capability_parses(self) -> None:
        for capability in SuiteCapability:
            with (
                self.subTest(capability=capability.value),
                mock.patch.dict(
                    os.environ,
                    {SUITE_CAPABILITY_ENV: capability.value},
                    clear=True,
                ),
            ):
                self.assertIs(suite_capability(), capability)

    def test_capabilities_select_exact_accessibility_identities(self) -> None:
        expected = {
            SuiteCapability.COMPANION_PROCESS: [],
            SuiteCapability.ACCESSIBILITY_READ: self.READ_TESTS,
            SuiteCapability.ACCESSIBILITY_INTERACTION: self.INTERACTION_TESTS,
        }
        for capability, names in expected.items():
            with (
                self.subTest(capability=capability.value),
                mock.patch.dict(
                    os.environ,
                    {SUITE_CAPABILITY_ENV: capability.value},
                    clear=True,
                ),
            ):
                discovered, selected = self.selected()
                if capability is SuiteCapability.ACCESSIBILITY_INTERACTION:
                    self.assertIs(selected, discovered)
                else:
                    self.assertIsNot(selected, discovered)
                self.assertEqual(self.names(selected), names)
                self.assertEqual(
                    [
                        name
                        for name, required in self.REQUIREMENTS.items()
                        if suite_supports(required)
                    ],
                    names,
                )

    def test_empty_and_unknown_capabilities_fail_closed(self) -> None:
        for configured in ("", "unknown"):
            with (
                self.subTest(configured=configured),
                mock.patch.dict(
                    os.environ,
                    {SUITE_CAPABILITY_ENV: configured},
                    clear=True,
                ),
                self.assertRaisesRegex(HarnessError, "not one of"),
            ):
                suite_capability()


class SharedCompanionReadinessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        super().setUp()
        self.previous = (harness._companion, harness._acquisition_failure)
        harness._companion = None
        harness._acquisition_failure = None

    def tearDown(self) -> None:
        harness._companion, harness._acquisition_failure = self.previous
        super().tearDown()

    @mock.patch.dict(
        os.environ,
        {SUITE_CAPABILITY_ENV: SuiteCapability.COMPANION_PROCESS.value},
        clear=True,
    )
    async def test_process_capability_does_not_probe_accessibility(self) -> None:
        environment = mock.sentinel.environment
        made = mock.Mock()
        with (
            mock.patch.object(
                harness,
                "shared_environment",
                new=mock.AsyncMock(return_value=environment),
            ),
            mock.patch.object(harness, "Companion", return_value=made),
            mock.patch.object(
                harness,
                "wait_for_accessibility",
                new=mock.AsyncMock(),
            ) as wait_for_accessibility,
            mock.patch.object(harness.atexit, "register") as register,
        ):
            acquired = await shared_companion()

        self.assertIs(acquired, made)
        self.assertIs(harness._companion, made)
        wait_for_accessibility.assert_not_awaited()
        register.assert_called_once_with(made.stop)

    async def test_accessibility_capabilities_probe_before_caching(self) -> None:
        for capability in (
            SuiteCapability.ACCESSIBILITY_READ,
            SuiteCapability.ACCESSIBILITY_INTERACTION,
        ):
            with self.subTest(capability=capability.value):
                harness._companion = None
                environment = mock.sentinel.environment
                made = mock.Mock()

                async def probe(*_args: object) -> None:
                    self.assertIsNone(harness._companion)

                with (
                    mock.patch.dict(
                        os.environ,
                        {SUITE_CAPABILITY_ENV: capability.value},
                        clear=True,
                    ),
                    mock.patch.object(
                        harness,
                        "shared_environment",
                        new=mock.AsyncMock(return_value=environment),
                    ),
                    mock.patch.object(harness, "Companion", return_value=made),
                    mock.patch.object(
                        harness,
                        "wait_for_accessibility",
                        new=mock.AsyncMock(side_effect=probe),
                    ) as wait_for_accessibility,
                    mock.patch.object(harness.atexit, "register") as register,
                ):
                    acquired = await shared_companion()

                self.assertIs(acquired, made)
                self.assertIs(harness._companion, made)
                wait_for_accessibility.assert_awaited_once_with(environment, made)
                register.assert_called_once_with(made.stop)

    async def test_readiness_failure_and_cancellation_are_cached(self) -> None:
        for error in (HarnessError("not ready"), asyncio.CancelledError()):
            with self.subTest(error=type(error).__name__):
                harness._companion = None
                harness._acquisition_failure = None
                made = mock.Mock()
                with (
                    mock.patch.dict(
                        os.environ,
                        {
                            SUITE_CAPABILITY_ENV: (
                                SuiteCapability.ACCESSIBILITY_READ.value
                            )
                        },
                        clear=True,
                    ),
                    mock.patch.object(
                        harness,
                        "shared_environment",
                        new=mock.AsyncMock(return_value=mock.sentinel.environment),
                    ),
                    mock.patch.object(harness, "Companion", return_value=made),
                    mock.patch.object(
                        harness,
                        "wait_for_accessibility",
                        new=mock.AsyncMock(side_effect=error),
                    ),
                    mock.patch.object(harness.atexit, "register") as register,
                ):
                    with self.assertRaises(type(error)) as raised:
                        await shared_companion()

                self.assertIs(raised.exception, error)
                self.assertIs(harness._acquisition_failure, error)
                self.assertIsNone(harness._companion)
                made.stop.assert_called_once_with()
                register.assert_not_called()

                with (
                    mock.patch.dict(
                        os.environ,
                        {
                            SUITE_CAPABILITY_ENV: (
                                SuiteCapability.ACCESSIBILITY_READ.value
                            )
                        },
                        clear=True,
                    ),
                    mock.patch.object(harness, "Companion") as construct,
                    self.assertRaises(type(error)) as repeated,
                ):
                    await shared_companion()
                self.assertIs(repeated.exception, error)
                construct.assert_not_called()

    async def test_invalid_capability_fails_before_process_construction(self) -> None:
        for configured in ("", "unknown"):
            with (
                self.subTest(configured=configured),
                mock.patch.dict(
                    os.environ,
                    {SUITE_CAPABILITY_ENV: configured},
                    clear=True,
                ),
                mock.patch.object(harness, "Companion") as construct,
                self.assertRaisesRegex(HarnessError, "not one of"),
            ):
                await shared_companion()
            construct.assert_not_called()


class AccessibilityReadinessTests(unittest.IsolatedAsyncioTestCase):
    async def test_probe_uses_the_selected_client_not_the_setup_client(self) -> None:
        environment = SimpleNamespace(
            idb_bin=Path("/selected-idb"),
            idb_args=("--selected-argument",),
            setup_idb_bin=Path("/setup-idb"),
        )
        selected = mock.AsyncMock(return_value=Completed(0, b"\xff", b"\xfe"))
        with mock.patch.object(harness, "run", new=selected):
            await wait_for_accessibility(
                environment,
                SimpleNamespace(address="/tmp/companion.sock"),
            )

        selected.assert_awaited_once_with(
            [
                "/selected-idb",
                "--selected-argument",
                "--companion",
                "/tmp/companion.sock",
                *harness.ACCESSIBILITY_PROBE_ARGS,
            ],
            timeout=harness.DEFAULT_COMMAND_TIMEOUT_SECONDS,
        )


class FailureReportingTests(unittest.TestCase):
    def test_reports_a_failed_command_with_its_own_output(self) -> None:
        message = report_for("boom")

        self.assertIn("idb describe failed (rc=1)", message)
        self.assertIn("boom", message)

    def test_command_failure_includes_companion_exit_status(self) -> None:
        message = report_for("boom", companion_returncode=1)

        self.assertIn("idb describe failed (rc=1)", message)
        self.assertIn("has since exited with 1", message)

    def test_connection_failure_reports_companion_exit(self) -> None:
        message = report_for(CONNECTION_REFUSED, companion_returncode=1)

        self.assertTrue(
            message.startswith("The client could not reach the companion"),
            f"expected a connection failure, got: {message}",
        )
        self.assertIn("the companion exited with 1", message)
        self.assertIn("companion log", message)

    def test_connection_failure_reports_running_companion(self) -> None:
        message = report_for(CONNECTION_REFUSED)

        self.assertTrue(
            message.startswith("The client could not reach the companion"),
            f"expected a connection failure, got: {message}",
        )
        self.assertIn("the companion is still running", message)

    # Test both strict settings independently of the runner's environment.
    @mock.patch.dict(os.environ, {STRICT_ENV: "0"})
    def test_skips_when_the_host_cannot_spawn_in_the_guest(self) -> None:
        case = HarnessCaseStub()

        with self.assertRaises(Skipped) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn("SimLaunchHostService", str(raised.exception))

    @mock.patch.dict(os.environ, {STRICT_ENV: "1"})
    def test_strict_mode_fails_when_host_service_is_unavailable(self) -> None:
        case = HarnessCaseStub()

        with self.assertRaises(Failed) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn(f"{STRICT_ENV}=1", str(raised.exception))


class CommandTestCaseStub(HarnessCaseStub):
    idb = IdbEndToEndTestCase.idb
    idb_expect_failure = IdbEndToEndTestCase.idb_expect_failure
    fail_or_skip_for = IdbEndToEndTestCase.fail_or_skip_for
    run_client = IdbEndToEndTestCase.run_client


class ExpectedFailureTest(unittest.IsolatedAsyncioTestCase):
    async def result(
        self,
        completed: Completed,
        *,
        expected_error: str | Sequence[str] = "not a dictionary",
        companion_returncode: int | None = None,
    ) -> Completed:
        case = CommandTestCaseStub(companion_returncode)
        with mock.patch.object(
            harness,
            "run",
            new=mock.AsyncMock(return_value=completed),
        ):
            return await case.idb_expect_failure(
                "send-notification",
                "com.example",
                "[]",
                expected_error=expected_error,
            )

    async def test_accepts_only_the_named_command_rejection(self) -> None:
        completed = Completed(
            1,
            b"",
            b"Failed to deserialize notification json: not a dictionary\n",
        )

        self.assertEqual(await self.result(completed), completed)

    async def test_rejects_empty_expected_error_marker_sets_and_members(self) -> None:
        completed = Completed(1, b"", b"not a dictionary\n")
        for expected_error in ((), ("",), (" \t",)):
            with self.subTest(expected_error=expected_error):
                with self.assertRaisesRegex(Failed, "expected error marker"):
                    await self.result(completed, expected_error=expected_error)

    async def test_rejects_an_unrelated_command_failure(self) -> None:
        with self.assertRaisesRegex(Failed, "unexpected reason"):
            await self.result(Completed(1, b"", b"target is not booted\n"))

    async def test_rejects_a_failure_when_the_companion_died(self) -> None:
        with self.assertRaisesRegex(Failed, "has since exited with 9"):
            await self.result(
                Completed(1, b"", b"not a dictionary\n"),
                companion_returncode=9,
            )


class CompanionLifecycleTests(unittest.TestCase):
    def test_running_companion_has_no_exit_error(self) -> None:
        self.assertIsNone(companion(None).died())

    def test_companion_exit_error_includes_status_and_log(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "companion.log"
            log.write_text("last thing the companion served\n")

            died = companion(9, log).died()

        assert died is not None
        self.assertIsInstance(died, CompanionDied)
        self.assertIn("exited with 9", str(died))
        self.assertIn("last thing the companion served", str(died))

    def test_companion_exit_stops_the_suite(self) -> None:
        case = HarnessCaseStub(companion_returncode=1)

        reported_by(case, "boom")

        self.assertTrue(case._result.shouldStop)

    def test_command_failure_does_not_stop_the_suite(self) -> None:
        case = HarnessCaseStub()

        reported_by(case, "boom")

        self.assertFalse(case._result.shouldStop)

    def test_connection_failure_with_live_companion_does_not_stop_the_suite(
        self,
    ) -> None:
        case = HarnessCaseStub()

        reported_by(case, CONNECTION_REFUSED)

        self.assertFalse(case._result.shouldStop)


class DeadCompanionStopsTheSuiteTests(unittest.TestCase):
    class Suite(IdbEndToEndTestCase):
        ran: list[str] = []

        async def asyncSetUp(self) -> None:
            self.companion = companion(1)
            self.check_companion()

        async def case_first(self) -> None:
            self.ran.append("first")

        async def case_second(self) -> None:
            self.ran.append("second")

    def test_companion_exit_fails_setup_and_stops_remaining_tests(self) -> None:
        self.Suite.ran = []
        suite = unittest.TestSuite(
            [self.Suite("case_first"), self.Suite("case_second")]
        )
        result = unittest.TestResult()

        suite.run(result)

        self.assertEqual(self.Suite.ran, [])
        self.assertEqual(result.testsRun, 1)
        self.assertEqual(len(result.errors), 1)
        self.assertIn("exited with 1", result.errors[0][1])
        self.assertTrue(result.shouldStop)


def reading(listapps: Completed, plutil: Completed) -> Run:
    """Return canned listapps and plutil responses."""

    async def run(
        argv: Sequence[str], timeout: float, stdin: bytes | None = None
    ) -> Completed:
        return plutil if argv[0] == "plutil" else listapps

    return run


class InstalledBundleIdsTests(unittest.IsolatedAsyncioTestCase):
    async def bundle_ids(self, listapps: Completed, plutil: Completed) -> set[str]:
        with mock.patch.object(harness, "run", reading(listapps, plutil)):
            return await Simctl("UDID", Path("/device-set")).installed_bundle_ids()

    async def test_parses_installed_bundle_ids(self) -> None:
        installed = await self.bundle_ids(
            Completed(0, LISTAPPS_PLIST, b""), Completed(0, LISTAPPS_JSON, b"")
        )

        self.assertEqual(installed, {"com.apple.Preferences"})

    async def test_a_failing_listapps_is_an_error(self) -> None:
        with self.assertRaises(HarnessError) as raised:
            await self.bundle_ids(FAILED, Completed(0, LISTAPPS_JSON, b""))

        self.assertIn("simctl listapps failed (rc=1)", str(raised.exception))

    async def test_a_failing_plutil_is_an_error(self) -> None:
        with self.assertRaises(HarnessError) as raised:
            await self.bundle_ids(Completed(0, LISTAPPS_PLIST, b""), FAILED)

        self.assertIn("could not be converted to JSON", str(raised.exception))


class RunningBundleIdsTests(unittest.TestCase):
    def test_only_apps_with_positive_pids_are_running(self) -> None:
        self.assertEqual(
            running_bundle_ids_from_listing(LAUNCHCTL_LISTING),
            {"com.apple.mobilesafari"},
        )

    def test_empty_listing_has_no_running_apps(self) -> None:
        self.assertEqual(running_bundle_ids_from_listing("PID\tStatus\tLabel\n"), set())


class DeadlineTests(unittest.TestCase):
    def test_positive_timeout_leaves_time_remaining(self) -> None:
        deadline = Deadline(60.0)

        self.assertFalse(deadline.passed)
        self.assertGreater(deadline.remaining, 0)
        self.assertLessEqual(deadline.remaining, 60.0)

    def test_zero_timeout_is_expired(self) -> None:
        deadline = Deadline(0.0)

        self.assertTrue(deadline.passed)
        self.assertLessEqual(deadline.remaining, 0)


@mock.patch.object(harness, "POLL_INTERVAL_SECONDS", 0.0)
class WaitUntilTests(unittest.IsolatedAsyncioTestCase):
    async def test_returns_successful_poll_result(self) -> None:
        asked = 0

        async def poll() -> str:
            nonlocal asked
            asked += 1
            return "ready"

        self.assertEqual(await wait_until("Never", 60.0, poll), "ready")
        self.assertEqual(asked, 1)

    async def test_retries_on_not_ready(self) -> None:
        answers = [NotReady("still coming up"), NotReady("still coming up"), "ready"]

        async def poll() -> str:
            answer = answers.pop(0)
            if isinstance(answer, NotReady):
                raise answer
            return answer

        self.assertEqual(await wait_until("Never", 60.0, poll), "ready")
        self.assertEqual(answers, [])

    async def test_timeout_includes_last_not_ready_reason(self) -> None:
        async def poll() -> str:
            raise NotReady("no accessibility translation object")

        with self.assertRaises(HarnessError) as raised:
            await wait_until("The simulator did not begin serving", 0.0, poll)

        self.assertEqual(
            str(raised.exception),
            "The simulator did not begin serving within 0s: "
            "no accessibility translation object",
        )

    async def test_zero_timeout_still_polls_once(self) -> None:
        asked = 0

        async def poll() -> str:
            nonlocal asked
            asked += 1
            return "ready"

        self.assertEqual(await wait_until("Never", 0.0, poll), "ready")
        self.assertEqual(asked, 1)

    async def test_other_exceptions_propagate_without_retry(self) -> None:
        async def poll() -> str:
            raise HarnessError("the companion is gone")

        with self.assertRaises(HarnessError) as raised:
            await wait_until("Never", 60.0, poll)

        self.assertEqual(str(raised.exception), "the companion is gone")


class EnvironmentSelectionTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        super().setUp()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.built_companion = self.root / "built-companion"
        self.installed_companion = self.root / "installed-companion"
        for path in (self.built_companion, self.installed_companion):
            path.touch()
            path.chmod(0o755)
        self.environment = {
            "DEVICE_UDID": "test-simulator",
            "DEVICE_SET_PATH": str(self.root),
            "IDB_BIN": str(self.built_companion),
            "IDB_E2E_COMPANION_PATH": str(self.built_companion),
            "IDB_E2E_RECORDER_PATH": str(self.built_companion),
            "IDB_COMPANION_PATH": str(self.installed_companion),
        }

    async def test_companion_selection_with_both_environment_variables(self) -> None:
        with (
            mock.patch.dict(os.environ, self.environment, clear=True),
            mock.patch.object(
                Simctl, "state", new=mock.AsyncMock(return_value="Booted")
            ),
        ):
            environment = await harness.Environment.resolve()
        self.assertEqual(environment.companion_path, self.built_companion)

    async def test_generic_companion_variable_alone(self) -> None:
        del self.environment["IDB_E2E_COMPANION_PATH"]
        with (
            mock.patch.dict(os.environ, self.environment, clear=True),
            mock.patch.object(
                Simctl, "state", new=mock.AsyncMock(return_value="Booted")
            ),
        ):
            with self.assertRaisesRegex(
                HarnessError, "IDB_E2E_COMPANION_PATH is not set"
            ):
                await harness.Environment.resolve()

    async def test_recorder_path_is_required(self) -> None:
        del self.environment["IDB_E2E_RECORDER_PATH"]
        with mock.patch.dict(os.environ, self.environment, clear=True):
            with self.assertRaisesRegex(
                HarnessError, "IDB_E2E_RECORDER_PATH is not set"
            ):
                await harness.Environment.resolve()


class RecordingResultTests(unittest.TestCase):
    class Suite(IdbEndToEndTestCase):
        async def asyncSetUp(self) -> None:
            self.recording.start_test(self.id())

        async def case_pass(self) -> None:
            pass

        async def case_fail(self) -> None:
            self.fail("intentional failure")

        async def case_cleanup_error(self) -> None:
            self.addCleanup(self.fail, "cleanup failed")

        async def case_skip(self) -> None:
            self.skipTest("intentional skip")

    def run_case(self, method: str) -> mock.Mock:
        recording = mock.Mock()
        recording.screenshot = mock.AsyncMock()
        case = self.Suite(method)
        case.recording = recording
        result = unittest.TestResult()
        case.run(result)
        recording.screenshot.assert_awaited_once()
        return recording

    def test_records_success(self) -> None:
        self.run_case("case_pass").finish_test.assert_called_once_with("passed")

    def test_records_failure(self) -> None:
        self.run_case("case_fail").finish_test.assert_called_once_with("failed")

    def test_includes_cleanup_failures(self) -> None:
        self.run_case("case_cleanup_error").finish_test.assert_called_once_with(
            "failed"
        )

    def test_records_skip(self) -> None:
        self.run_case("case_skip").finish_test.assert_called_once_with("skipped")


class UnavailableRecordingTests(unittest.IsolatedAsyncioTestCase):
    async def test_commands_remain_logged_after_encoder_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            process = mock.Mock()
            process.poll.return_value = 1
            process.returncode = 1
            process.stdin = io.BytesIO()
            with (
                mock.patch.object(
                    recording_module.subprocess, "Popen", return_value=process
                ),
                mock.patch.dict(os.environ, {}, clear=True),
            ):
                recording = Recording(
                    Path("/recorder"), "udid", Path("/set"), Path(directory), "test"
                )
                try:
                    await recording.wait_until_ready()
                    recording.start_test("test_failure")
                    recording.command(["idb", "ui", "wait", 'a "quoted" marker'])
                    recording.finish_test("failed")
                    recording.stop()
                    events = [
                        json.loads(line)
                        for line in Path(recording.trace.name).read_text().splitlines()
                    ]
                finally:
                    recording.trace.close()
        self.assertFalse(recording.ready)
        self.assertIn("exited with 1", recording.error)
        command = next(event for event in events if event["event"] == "command_started")
        self.assertEqual(command["argv"], ["idb", "ui", "wait", 'a "quoted" marker'])
        self.assertEqual(events[-1]["status"], "failed")
        self.assertEqual(
            sum(event["event"] == "recording_finished" for event in events), 1
        )


class BinaryPathTests(unittest.IsolatedAsyncioTestCase):
    """The paths the harness hands to `simctl spawn`.

    A simulator's `launchd_sim` resolves the program path case-sensitively, even
    where the filesystem it sits on does not. A path that differs from the one on
    disk only in case therefore opens, stats and code-signs perfectly well on the
    host, and is refused by the guest with an error naming neither the file nor
    the case:

        domain=com.apple.CoreSimulator.LaunchdSimError, code=111
        Underlying error (domain=SimXPCErrorDomain, code=111):
            Invalid or missing Program/ProgramArguments

    Such a path reaches the harness whenever an ancestor directory is spelled
    differently from the one that exists -- on a case-insensitive filesystem,
    `mkdir Build` beside an existing `build` silently keeps `build`.

    These go through `Environment.resolve`, which is where the paths the suite
    actually spawns come from: what a test hands `simctl` is either a binary
    the environment named, or something derived from one -- and a derived path
    inherits whatever spelling its companion was resolved to.
    """

    def setUp(self) -> None:
        # Resolved up front: /tmp is a symlink on macOS, and the behaviour under
        # test is the spelling of a path, not where symlinks lead.
        self.directory = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.directory, True)
        # The distribution as the public job lays it out: the companion with its
        # Resources/ beside it, under the lowercase `build/` that
        # `pip install .` leaves in the checkout.
        self.distribution = self.directory / "build" / "Distribution"
        (self.distribution / "Resources").mkdir(parents=True)
        self.companion = self.distribution / "idb_companion"
        self.companion.write_text("#!/bin/sh\n")
        self.companion.chmod(0o755)

    def as_exported(self, path: Path) -> Path:
        """The same path spelled `Build`, the way the workflow exports it."""
        lowercase = self.directory / "build"
        return self.directory / "Build" / path.relative_to(lowercase)

    def skip_unless_both_spellings_exist(self, path: Path) -> None:
        if not path.exists():
            raise unittest.SkipTest(
                "a case-sensitive filesystem cannot present the two spellings"
            )

    async def resolve(self, companion: Path) -> harness.Environment:
        environment = {
            "DEVICE_UDID": "test-simulator",
            "DEVICE_SET_PATH": str(self.directory),
            "IDB_BIN": str(self.companion),
            "IDB_E2E_COMPANION_PATH": str(companion),
            "IDB_E2E_RECORDER_PATH": str(self.companion),
        }
        with (
            mock.patch.dict(os.environ, environment, clear=True),
            mock.patch.object(
                Simctl, "state", new=mock.AsyncMock(return_value="Booted")
            ),
        ):
            return await harness.Environment.resolve()

    async def test_a_companion_is_resolved_to_the_path_it_was_given(self) -> None:
        resolved = await self.resolve(self.companion)

        self.assertEqual(resolved.companion_path, self.companion)

    # The spelling on disk, so that what reaches `launchd_sim` is a path it
    # recognises rather than one that merely opens.
    async def test_a_differently_cased_companion_resolves_to_the_path_on_disk(
        self,
    ) -> None:
        requested = self.as_exported(self.companion)
        self.skip_unless_both_spellings_exist(requested)

        resolved = await self.resolve(requested)

        self.assertEqual(resolved.companion_path, self.companion)

    # And so everything derived beside it is spelled the way the guest needs,
    # which is what makes one corrected variable enough for the whole suite.
    async def test_what_is_derived_beside_a_companion_carries_its_corrected_case(
        self,
    ) -> None:
        requested = self.as_exported(self.companion)
        self.skip_unless_both_spellings_exist(requested)

        resolved = await self.resolve(requested)

        self.assertEqual(
            resolved.fixture_app,
            self.distribution / "Resources" / harness.FIXTURE_APP_NAME,
        )
        self.assertEqual(
            resolved.guest_binary,
            self.distribution / "Resources" / "SimulatorFrameworkBridge-iOS",
        )

    async def test_a_companion_that_is_not_there_under_either_spelling_is_refused(
        self,
    ) -> None:
        absent = self.directory / "Absent" / self.companion.name

        with self.assertRaises(harness.HarnessError):
            await self.resolve(absent)


class SubprocessTimeoutTests(unittest.IsolatedAsyncioTestCase):
    async def test_preserves_binary_output_input_environment_and_exit_code(
        self,
    ) -> None:
        code = (
            "import os,sys; "
            "sys.stdout.buffer.write(os.environ['IDB_TEST_VALUE'].encode() + "
            "sys.stdin.buffer.read()[::-1]); "
            "sys.stderr.buffer.write(b'\\xff'); sys.exit(7)"
        )
        result = await harness.run(
            [sys.executable, "-c", code],
            timeout=10,
            stdin=b"\x00\xfe",
            env={**os.environ, "IDB_TEST_VALUE": "prefix"},
        )

        self.assertEqual(result, Completed(7, b"prefix\xfe\x00", b"\xff"))

    async def test_reports_timeout_for_a_running_process(self) -> None:
        with self.assertRaisesRegex(HarnessError, "did not finish within"):
            await harness.run(
                [sys.executable, "-c", "import time; time.sleep(30)"], timeout=0.5
            )

    async def test_timeout_with_inherited_output_pipes(self) -> None:
        directory = self.enterContext(tempfile.TemporaryDirectory())
        ready = Path(directory) / "ready"
        stop = Path(directory) / "stop"
        exited = Path(directory) / "exited"
        child = (
            "import time; from pathlib import Path\n"
            "for _ in range(3000):\n"
            f"    if Path({str(stop)!r}).exists(): break\n"
            "    time.sleep(0.01)\n"
            f"Path({str(exited)!r}).touch()\n"
        )
        parent = (
            "import subprocess,sys,time; from pathlib import Path; "
            f"subprocess.Popen([sys.executable, '-c', {child!r}]); "
            f"Path({str(ready)!r}).touch(); time.sleep(30)"
        )
        process = None
        create_process = asyncio.create_subprocess_exec

        async def wait_for_file(path: Path) -> None:
            while not path.is_file():
                await asyncio.sleep(0.01)

        async def cleanup() -> None:
            if process is not None and process.returncode is None:
                try:
                    process.kill()
                except ProcessLookupError:
                    pass
            stop.touch()
            try:
                if ready.is_file():
                    await asyncio.wait_for(wait_for_file(exited), timeout=10)
            finally:
                if process is not None:
                    await asyncio.wait_for(process.wait(), timeout=10)

        self.addAsyncCleanup(cleanup)

        async def create_ready_process(*args, **kwargs):
            nonlocal process
            process = await create_process(*args, **kwargs)
            # Start the harness deadline only after a descendant owns the outputs.
            await asyncio.wait_for(wait_for_file(ready), timeout=10)
            return process

        self.enterContext(
            mock.patch.object(
                asyncio, "create_subprocess_exec", side_effect=create_ready_process
            )
        )
        with self.assertRaisesRegex(HarnessError, "did not finish within"):
            await asyncio.wait_for(
                harness.run([sys.executable, "-c", parent], timeout=0.5), timeout=12
            )
        self.assertTrue(ready.is_file(), "Descendant must be spawned before timeout")
        self.assertFalse(exited.is_file(), "Descendant must still hold the outputs")
