# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test failure reporting, process checks and polling without a simulator.

The *_tests.py name excludes this module from e2e unittest discovery, which
uses test*.py. Run it separately with python -m unittest EndToEndTests.harness_tests.
"""

from __future__ import annotations

import io
import json
import os
import tempfile
import unittest
from pathlib import Path
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
    mutation_lock_path,
    NotReady,
    running_bundle_ids_from_listing,
    Simctl,
    SimulatorMutationLock,
    STRICT_ENV,
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


class TestCaseStub:
    def __init__(self, companion_returncode: int | None = None) -> None:
        self.companion = companion(companion_returncode)
        self._result = unittest.TestResult()

    _stop_suite = IdbEndToEndTestCase._stop_suite

    def fail(self, message: str) -> NoReturn:
        raise Failed(message)

    def skipTest(self, reason: str) -> NoReturn:
        raise Skipped(reason)


def report_for(stderr: str, companion_returncode: int | None = None) -> str:
    return reported_by(TestCaseStub(companion_returncode), stderr)


def reported_by(case: TestCaseStub, stderr: str) -> str:
    try:
        IdbEndToEndTestCase.fail_or_skip_for(
            case, "describe", Completed(1, b"", stderr.encode())
        )
    except Failed as failed:
        return str(failed)
    raise AssertionError("fail_or_skip_for reported no failure")


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
        case = TestCaseStub()

        with self.assertRaises(Skipped) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn("SimLaunchHostService", str(raised.exception))

    @mock.patch.dict(os.environ, {STRICT_ENV: "1"})
    def test_strict_mode_fails_when_host_service_is_unavailable(self) -> None:
        case = TestCaseStub()

        with self.assertRaises(Failed) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn(f"{STRICT_ENV}=1", str(raised.exception))


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
        case = TestCaseStub(companion_returncode=1)

        reported_by(case, "boom")

        self.assertTrue(case._result.shouldStop)

    def test_command_failure_does_not_stop_the_suite(self) -> None:
        case = TestCaseStub()

        reported_by(case, "boom")

        self.assertFalse(case._result.shouldStop)

    def test_connection_failure_with_live_companion_does_not_stop_the_suite(
        self,
    ) -> None:
        case = TestCaseStub()

        reported_by(case, CONNECTION_REFUSED)

        self.assertFalse(case._result.shouldStop)


class DeadCompanionStopsTheSuiteTests(unittest.TestCase):
    class Suite(IdbEndToEndTestCase):
        ran: list[str] = []

        async def asyncSetUp(self) -> None:
            self.companion = companion(1)
            self.check_companion()

        async def test_first(self) -> None:
            self.ran.append("first")

        async def test_second(self) -> None:
            self.ran.append("second")

    def test_companion_exit_fails_setup_and_stops_remaining_tests(self) -> None:
        self.Suite.ran = []
        suite = unittest.TestSuite(
            [self.Suite("test_first"), self.Suite("test_second")]
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


class SimulatorMutationLockTests(unittest.TestCase):
    def test_the_path_is_shared_per_device_and_distinct_between_devices(self) -> None:
        device_set = Path("/tmp/device-set")

        self.assertEqual(
            mutation_lock_path(device_set, "DEVICE-A"),
            device_set / ".idb-e2e-mutation-DEVICE-A.lock",
        )
        self.assertNotEqual(
            mutation_lock_path(device_set, "DEVICE-A"),
            mutation_lock_path(device_set, "DEVICE-B"),
        )

    def test_a_second_owner_cannot_acquire_the_simulator_until_release(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = mutation_lock_path(Path(directory), "DEVICE")
            owner = SimulatorMutationLock(path)
            contender = SimulatorMutationLock(path)
            self.addCleanup(owner.close)
            self.addCleanup(contender.close)
            owner.acquire()

            with self.assertRaises(BlockingIOError):
                contender.acquire(blocking=False)

            owner.close()
            contender.acquire(blocking=False)


class MutationLockAcquisitionTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.previous_lock = harness._mutation_lock
        harness._mutation_lock = None

    def tearDown(self) -> None:
        if harness._mutation_lock is not None:
            harness._mutation_lock.close()
        harness._mutation_lock = self.previous_lock

    async def test_retries_nonblocking_contention_and_logs_the_lock(self) -> None:
        path = Path("/tmp/device-set/.idb-e2e-mutation-DEVICE.lock")
        lock = mock.Mock()
        lock.acquire.side_effect = [BlockingIOError(), None]
        with (
            mock.patch.object(harness, "mutation_lock_path", return_value=path),
            mock.patch.object(harness, "SimulatorMutationLock", return_value=lock),
            mock.patch.object(harness.asyncio, "sleep", new=mock.AsyncMock()) as sleep,
            mock.patch.object(harness.atexit, "register"),
            mock.patch.object(harness._LOGGER, "info") as log,
        ):
            await harness.acquire_mutation_lock(Path("/tmp/device-set"), "DEVICE")

        self.assertEqual(
            lock.acquire.call_args_list,
            [mock.call(blocking=False), mock.call(blocking=False)],
        )
        sleep.assert_awaited_once_with(harness.POLL_INTERVAL_SECONDS)
        log.assert_any_call(
            "Waiting up to %.0fs for simulator mutation lock: udid=%s path=%s",
            harness.MUTATION_LOCK_TIMEOUT_SECONDS,
            "DEVICE",
            path,
        )

    async def test_contention_timeout_names_the_udid_and_path(self) -> None:
        path = Path("/tmp/device-set/.idb-e2e-mutation-DEVICE.lock")
        lock = mock.Mock()
        lock.acquire.side_effect = BlockingIOError()
        with (
            mock.patch.object(harness, "mutation_lock_path", return_value=path),
            mock.patch.object(harness, "SimulatorMutationLock", return_value=lock),
            mock.patch.object(harness._LOGGER, "info"),
        ):
            with self.assertRaisesRegex(
                HarnessError,
                rf"DEVICE.*{path}.*within 0s",
            ):
                await harness.acquire_mutation_lock(
                    Path("/tmp/device-set"),
                    "DEVICE",
                    timeout=0,
                )

        lock.close.assert_called_once_with()
        self.assertIsNone(harness._mutation_lock)

    async def test_open_failure_is_a_contextual_harness_error(self) -> None:
        path = Path("/tmp/device-set/.idb-e2e-mutation-DEVICE.lock")
        with (
            mock.patch.object(harness, "mutation_lock_path", return_value=path),
            mock.patch.object(
                harness,
                "SimulatorMutationLock",
                side_effect=OSError("read-only file system"),
            ),
        ):
            with self.assertRaisesRegex(
                HarnessError,
                rf"open.*DEVICE.*{path}.*read-only file system",
            ):
                await harness.acquire_mutation_lock(
                    Path("/tmp/device-set"),
                    "DEVICE",
                )


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

        async def test_pass(self) -> None:
            pass

        async def test_fail(self) -> None:
            self.fail("intentional failure")

        async def test_cleanup_error(self) -> None:
            self.addCleanup(self.fail, "cleanup failed")

        async def test_skip(self) -> None:
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
        self.run_case("test_pass").finish_test.assert_called_once_with("passed")

    def test_records_failure(self) -> None:
        self.run_case("test_fail").finish_test.assert_called_once_with("failed")

    def test_includes_cleanup_failures(self) -> None:
        self.run_case("test_cleanup_error").finish_test.assert_called_once_with(
            "failed"
        )

    def test_records_skip(self) -> None:
        self.run_case("test_skip").finish_test.assert_called_once_with("skipped")


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


if __name__ == "__main__":
    unittest.main()
