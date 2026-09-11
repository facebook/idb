# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test failure reporting, process checks and polling without a simulator.

The *_tests.py name excludes this module from e2e unittest discovery, which
uses test*.py. Run it separately with python -m unittest EndToEndTests.harness_tests.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from typing import Awaitable, Callable, NoReturn, Sequence
from unittest import mock

from . import harness
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
    NotReady,
    running_bundle_ids_from_listing,
    Simctl,
    STRICT_ENV,
    wait_until,
)

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
    def test_excludes_exited_apps_and_daemons(self) -> None:
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


if __name__ == "__main__":
    unittest.main()
