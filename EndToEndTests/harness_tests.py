# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The harness's own decisions, taken apart from the simulator.

``fail_or_skip_for`` decides what a non-zero ``idb`` exit is reported as, and
every test in the suite reaches its own verdict through it. It reads nothing
but the companion and reports through ``fail`` and ``skipTest``, so it can be
called with a stand-in for the test case. Deciding that a companion has died
and the run should end, and polling until something is ready, are likewise
pure. All of them run anywhere, unlike the rest of the suite.

Named ``harness_tests`` rather than ``test_harness`` deliberately. The
end-to-end job discovers its tests with ``unittest discover``, whose default
pattern is ``test*.py``, so under this name these cannot be swept into a run
that leases a simulator and sets ``IDB_E2E_STRICT``. They are the environment,
not the subject: a red line in the end-to-end job should mean idb is broken.
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
    Companion,
    CompanionDied,
    Completed,
    Deadline,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
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

# `simctl listapps` writes an old-style plist, which is why the harness pipes it
# through `plutil` rather than reading it directly.
LISTAPPS_PLIST = b'{ "com.apple.Preferences" = { CFBundleName = Settings; }; }'
LISTAPPS_JSON = b'{"com.apple.Preferences": {"CFBundleName": "Settings"}}'
FAILED = Completed(1, b"", b"the simulator is not booted")

Run = Callable[..., Awaitable[Completed]]


class Failed(Exception):
    """What the stand-in raises for ``fail``."""


class Skipped(Exception):
    """What the stand-in raises for ``skipTest``."""


class ProcessStub:
    def __init__(self, returncode: int | None) -> None:
        self.returncode = returncode

    def poll(self) -> int | None:
        return self.returncode


def companion(returncode: int | None, log_path: Path | None = None) -> Companion:
    """A real ``Companion`` over a stand-in process, without starting one."""
    made = Companion.__new__(Companion)
    made.process = ProcessStub(returncode)
    made.log_path = log_path if log_path is not None else Path("/nonexistent.log")
    return made


class TestCaseStub:
    def __init__(self, companion_returncode: int | None = None) -> None:
        self.companion = companion(companion_returncode)
        self._result = unittest.TestResult()

    _stop_the_run = IdbEndToEndTestCase._stop_the_run

    def fail(self, message: str) -> NoReturn:
        raise Failed(message)

    def skipTest(self, reason: str) -> NoReturn:
        raise Skipped(reason)


def report_for(stderr: str, companion_returncode: int | None = None) -> str:
    """The message ``fail_or_skip_for`` reports for a failed ``idb describe``."""
    return reported_by(TestCaseStub(companion_returncode), stderr)


def reported_by(case: TestCaseStub, stderr: str) -> str:
    try:
        IdbEndToEndTestCase.fail_or_skip_for(
            case, "describe", Completed(1, b"", stderr.encode())
        )
    except Failed as failed:
        return str(failed)
    raise AssertionError("fail_or_skip_for reported no failure")


class FailureReportingTests(unittest.TestCase):
    def test_reports_a_failed_command_with_its_own_output(self) -> None:
        message = report_for("boom")

        self.assertIn("idb describe failed (rc=1)", message)
        self.assertIn("boom", message)

    def test_reports_a_failed_command_that_outlived_the_companion(self) -> None:
        message = report_for("boom", companion_returncode=1)

        self.assertIn("idb describe failed (rc=1)", message)
        self.assertIn("has since exited with 1", message)

    def test_reports_being_unable_to_reach_a_dead_companion(self) -> None:
        message = report_for(CONNECTION_REFUSED, companion_returncode=1)

        self.assertTrue(
            message.startswith("The client could not reach the companion"),
            f"expected the harness's own failure, got: {message}",
        )
        self.assertIn("the companion exited with 1", message)
        self.assertIn("companion log", message)

    def test_reports_being_unable_to_reach_a_live_companion(self) -> None:
        message = report_for(CONNECTION_REFUSED)

        self.assertTrue(
            message.startswith("The client could not reach the companion"),
            f"expected the harness's own failure, got: {message}",
        )
        self.assertIn("the companion is still running", message)

    # Both modes are stated rather than inherited. The end-to-end job sets
    # IDB_E2E_STRICT for the simulator tests, and these two cases are the
    # harness deciding what to do with it and without it, so a case that read
    # the runner's environment would be testing the runner.
    @mock.patch.dict(os.environ, {STRICT_ENV: "0"})
    def test_skips_when_the_host_cannot_spawn_in_the_guest(self) -> None:
        case = TestCaseStub()

        with self.assertRaises(Skipped) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn("SimLaunchHostService", str(raised.exception))

    @mock.patch.dict(os.environ, {STRICT_ENV: "1"})
    def test_fails_rather_than_skipping_for_that_host_under_strict(self) -> None:
        case = TestCaseStub()

        with self.assertRaises(Failed) as raised:
            IdbEndToEndTestCase.fail_or_skip_for(
                case, "describe", Completed(1, b"", HOST_SERVICE_UNAVAILABLE.encode())
            )

        self.assertIn(f"{STRICT_ENV}=1", str(raised.exception))


class CompanionLifecycleTests(unittest.TestCase):
    """The harness ending a run whose companion is gone."""

    def test_a_running_companion_has_not_died(self) -> None:
        self.assertIsNone(companion(None).died())

    def test_a_dead_companion_names_its_exit_and_carries_its_log(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "companion.log"
            log.write_text("last thing the companion served\n")

            died = companion(9, log).died()

        assert died is not None
        self.assertIsInstance(died, CompanionDied)
        self.assertIn("exited with 9", str(died))
        self.assertIn("last thing the companion served", str(died))

    def test_a_command_that_outlived_the_companion_ends_the_run(self) -> None:
        case = TestCaseStub(companion_returncode=1)

        reported_by(case, "boom")

        self.assertTrue(case._result.shouldStop)

    def test_a_command_that_failed_on_its_own_does_not_end_the_run(self) -> None:
        case = TestCaseStub()

        reported_by(case, "boom")

        self.assertFalse(case._result.shouldStop)

    def test_being_unable_to_reach_a_live_companion_does_not_end_the_run(self) -> None:
        # Not every unreachable companion is a dead one, and a run is only
        # abandoned for a companion that is actually gone.
        case = TestCaseStub()

        reported_by(case, CONNECTION_REFUSED)

        self.assertFalse(case._result.shouldStop)


class DeadCompanionStopsTheSuiteTests(unittest.TestCase):
    """The whole mechanism, through unittest, with no simulator involved."""

    class Suite(IdbEndToEndTestCase):
        ran: list[str] = []

        async def asyncSetUp(self) -> None:
            # Stands in for the shared environment and companion, so that what
            # is under test is the gate and not what supplies it.
            self.companion = companion(1)
            self.end_the_run_if_the_companion_died()

        async def test_first(self) -> None:
            self.ran.append("first")

        async def test_second(self) -> None:
            self.ran.append("second")

    def test_the_first_test_reports_the_death_and_no_later_test_runs(self) -> None:
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
    """Stands in for every subprocess ``installed_bundle_ids`` runs."""

    async def run(
        argv: Sequence[str], timeout: float, stdin: bytes | None = None
    ) -> Completed:
        return plutil if argv[0] == "plutil" else listapps

    return run


class InstalledBundleIdsTests(unittest.IsolatedAsyncioTestCase):
    """What simctl -- the ground truth the application tests cross-check
    against -- reports when it cannot be read."""

    async def bundle_ids(
        self, listapps: Completed, plutil: Completed
    ) -> set[str] | None:
        with mock.patch.object(harness, "run", reading(listapps, plutil)):
            return await Simctl("UDID", Path("/device-set")).installed_bundle_ids()

    async def test_a_listing_reports_what_is_installed(self) -> None:
        installed = await self.bundle_ids(
            Completed(0, LISTAPPS_PLIST, b""), Completed(0, LISTAPPS_JSON, b"")
        )

        self.assertEqual(installed, {"com.apple.Preferences"})

    async def test_a_failing_listapps_reports_nothing_installed(self) -> None:
        installed = await self.bundle_ids(FAILED, Completed(0, LISTAPPS_JSON, b""))

        # BUG: reports the same thing as an empty simulator, so a caller's
        # `if installed is not None` guard drops its cross-check without
        # saying so -- flipped in the following commit.
        self.assertIsNone(installed)

    async def test_a_failing_plutil_reports_nothing_installed(self) -> None:
        installed = await self.bundle_ids(Completed(0, LISTAPPS_PLIST, b""), FAILED)

        # BUG: as above -- the conversion failing is indistinguishable from
        # nothing being installed. Flipped in the following commit.
        self.assertIsNone(installed)


class DeadlineTests(unittest.TestCase):
    def test_a_deadline_in_the_future_has_not_passed(self) -> None:
        deadline = Deadline(60.0)

        self.assertFalse(deadline.passed)
        self.assertGreater(deadline.remaining, 0)
        self.assertLessEqual(deadline.remaining, 60.0)

    def test_a_deadline_of_no_time_has_passed(self) -> None:
        deadline = Deadline(0.0)

        self.assertTrue(deadline.passed)
        self.assertLessEqual(deadline.remaining, 0)


@mock.patch.object(harness, "POLL_INTERVAL_SECONDS", 0.0)
class WaitUntilTests(unittest.IsolatedAsyncioTestCase):
    """What a poll can say, and what each answer does to the wait."""

    async def test_a_poll_that_is_ready_returns_its_value(self) -> None:
        asked = 0

        async def poll() -> str:
            nonlocal asked
            asked += 1
            return "ready"

        self.assertEqual(await wait_until("Never", 60.0, poll), "ready")
        self.assertEqual(asked, 1)

    async def test_a_poll_is_asked_again_until_it_is_ready(self) -> None:
        answers = [NotReady("still coming up"), NotReady("still coming up"), "ready"]

        async def poll() -> str:
            answer = answers.pop(0)
            if isinstance(answer, NotReady):
                raise answer
            return answer

        self.assertEqual(await wait_until("Never", 60.0, poll), "ready")
        self.assertEqual(answers, [])

    async def test_the_timeout_names_what_it_was_waiting_for(self) -> None:
        async def poll() -> str:
            raise NotReady("it has no translation object to serve")

        with self.assertRaises(HarnessError) as raised:
            await wait_until("The simulator did not begin serving", 0.0, poll)

        self.assertEqual(
            str(raised.exception),
            "The simulator did not begin serving within 0s: "
            "it has no translation object to serve",
        )

    async def test_the_poll_is_asked_once_before_the_deadline_is_read(self) -> None:
        asked = 0

        async def poll() -> str:
            nonlocal asked
            asked += 1
            return "ready"

        self.assertEqual(await wait_until("Never", 0.0, poll), "ready")
        self.assertEqual(asked, 1)

    async def test_a_failure_that_is_not_not_ready_is_not_waited_out(self) -> None:
        async def poll() -> str:
            raise HarnessError("the companion is gone")

        with self.assertRaises(HarnessError) as raised:
            await wait_until("Never", 60.0, poll)

        self.assertEqual(str(raised.exception), "the companion is gone")


if __name__ == "__main__":
    unittest.main()
