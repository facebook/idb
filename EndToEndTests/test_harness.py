# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The harness's own decisions, taken apart from the simulator.

``fail_or_skip_for`` decides what a non-zero ``idb`` exit is reported as, and
every test in the suite reaches its own verdict through it. It reads nothing
but the companion and reports through ``fail`` and ``skipTest``, so it can be
called with a stand-in for the test case. Reading SpringBoard's pid out of a
``launchctl`` listing is likewise pure. Both run anywhere, unlike the rest of
the suite.
"""

from __future__ import annotations

import os
import unittest
from typing import NoReturn
from unittest import mock

from .harness import (
    Completed,
    IdbEndToEndTestCase,
    springboard_pid_from_listing,
    STRICT_ENV,
)

# `launchctl list` in the guest, cut down to the shape the harness reads: a
# header, a job launchd is keeping listed after it exited, and SpringBoard.
LAUNCHCTL_LISTING = """PID\tStatus\tLabel
-\t0\tcom.apple.SafariBookmarksSyncAgent
81\t0\tcom.apple.SpringBoard
92\t0\tcom.apple.SpringBoardServices
"""

CONNECTION_REFUSED = (
    "Failed to connect to companion at address DomainSocketAddress("
    "path='/tmp/idb-e2e-4xdxnimi/companion.sock'): [Errno 61] Connection refused"
)
HOST_SERVICE_UNAVAILABLE = (
    "SimLaunchHostService.RequestError: Exit Code 149 is not acceptable"
)


class Failed(Exception):
    """What the stand-in raises for ``fail``."""


class Skipped(Exception):
    """What the stand-in raises for ``skipTest``."""


class CompanionStub:
    def __init__(self, returncode: int | None) -> None:
        self.returncode = returncode
        self.process = self

    def poll(self) -> int | None:
        return self.returncode

    def log_excerpt(self, limit: int = 4000) -> str:
        return "<companion log>"

    def liveness_note(self) -> str:
        if self.returncode is None:
            return "the companion is still running"
        return f"the companion exited with {self.returncode}"


class TestCaseStub:
    def __init__(self, companion_returncode: int | None = None) -> None:
        self.companion = CompanionStub(companion_returncode)

    def fail(self, message: str) -> NoReturn:
        raise Failed(message)

    def skipTest(self, reason: str) -> NoReturn:
        raise Skipped(reason)


def report_for(stderr: str, companion_returncode: int | None = None) -> str:
    """The message ``fail_or_skip_for`` reports for a failed ``idb describe``."""
    case = TestCaseStub(companion_returncode)
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


class SpringBoardListingTests(unittest.TestCase):
    def test_reports_the_pid_of_a_running_springboard(self) -> None:
        self.assertEqual(springboard_pid_from_listing(LAUNCHCTL_LISTING), 81)

    def test_reports_nothing_for_a_job_launchd_lists_without_a_pid(self) -> None:
        listing = LAUNCHCTL_LISTING.replace(
            "81\t0\tcom.apple.SpringBoard", "-\t0\tcom.apple.SpringBoard"
        )

        self.assertIsNone(springboard_pid_from_listing(listing))

    def test_reports_nothing_when_springboard_is_not_listed(self) -> None:
        listing = LAUNCHCTL_LISTING.replace("81\t0\tcom.apple.SpringBoard\n", "")

        self.assertIsNone(springboard_pid_from_listing(listing))

    def test_does_not_take_another_job_for_springboard(self) -> None:
        listing = "PID\tStatus\tLabel\n92\t0\tcom.apple.SpringBoardServices\n"

        self.assertIsNone(springboard_pid_from_listing(listing))


if __name__ == "__main__":
    unittest.main()
