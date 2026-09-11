# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test app installation, launch, termination and removal using ReplHost.app."""

from __future__ import annotations

import json
from typing import Any

from .harness import HarnessError, IdbEndToEndTestCase, NotReady, wait_until

PID_REPORT_TIMEOUT_SECONDS = 120.0

APP_STOP_TIMEOUT_SECONDS = 60.0


def _leading_json_object(data: bytes) -> tuple[Any, int]:
    """Decode the first JSON value and return its end offset in the decoded text."""
    return json.JSONDecoder().raw_decode(data.decode(errors="replace"))


class ApplicationLifecycleTests(IdbEndToEndTestCase):
    async def test_install_launch_terminate_and_uninstall(self) -> None:
        bundle_id = await self.install_fixture_app()

        installed = await self.simctl.installed_bundle_ids()
        self.assertIn(bundle_id, installed, "simctl does not see the installed app")
        app = (await self.installed_apps())[bundle_id]
        self.assertEqual(app["install_type"], "user")
        self.assertNotEqual(app["process_state"], "Running")

        pid_file = self.make_temporary_directory() / "pid"
        await self.idb("launch", "--pid-file", str(pid_file), bundle_id)
        pid = json.loads(pid_file.read_text())["pid"]
        self.assertGreater(pid, 0)
        running = (await self.installed_apps())[bundle_id]
        self.assertEqual(running["process_state"], "Running")
        self.assertEqual(int(running["pid"]), pid)

        await self.idb("terminate", bundle_id)
        self.assertNotEqual(
            (await self.installed_apps())[bundle_id]["process_state"], "Running"
        )

        await self.idb("uninstall", bundle_id)
        self.assertNotIn(bundle_id, await self.installed_apps())
        installed = await self.simctl.installed_bundle_ids()
        self.assertNotIn(bundle_id, installed, "simctl still sees the uninstalled app")

    async def test_launching_an_unknown_bundle_fails(self) -> None:
        completed = await self.idb_expect_failure(
            "launch", "com.example.idb.not-installed"
        )
        self.assertTrue(
            completed.error_text.strip(), "a failed launch should explain itself"
        )

    async def test_list_apps_reports_system_applications(self) -> None:
        apps = await self.installed_apps()
        self.assertIn("com.apple.mobilesafari", apps)
        for row in apps.values():
            self.assertIn("name", row)
            self.assertIn("install_type", row)
            self.assertIn("process_state", row)


class LaunchOutputTests(IdbEndToEndTestCase):
    """Check PID output and app lifetime for launch --wait-for."""

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.bundle_id = await self.install_fixture_app()

    async def test_waiting_launch_reports_the_pid_on_stdout(self) -> None:
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            report, _ = _leading_json_object(
                await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            )
            self.assertIsInstance(report, dict)
            pid = report["pid"]
            self.assertGreater(pid, 0)

            running = (await self.installed_apps())[self.bundle_id]
            self.assertEqual(running["process_state"], "Running")
            self.assertEqual(int(running["pid"]), pid)

    async def test_the_launch_holds_the_app_open_until_it_is_stopped(self) -> None:
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            # Background the app while keeping the launch command attached.
            await self.idb("ui", "button", "HOME", check=False)
            self.assertIsNone(
                launch.returncode,
                "launch --wait-for should stay attached while the app runs",
            )
            self.assertEqual(
                (await self.installed_apps())[self.bundle_id]["process_state"],
                "Running",
            )

        # App termination may finish after the launch command exits.
        await self.wait_until_the_app_has_stopped()

    async def wait_until_the_app_has_stopped(self) -> None:
        async def stopped() -> None:
            app = (await self.installed_apps())[self.bundle_id]
            if app["process_state"] == "Running":
                raise NotReady("list-apps still reports it running")

        try:
            await wait_until(
                "Stopping the launch did not stop the app it was holding open",
                APP_STOP_TIMEOUT_SECONDS,
                stopped,
            )
        except HarnessError as error:
            self.fail(str(error))

    async def test_the_pid_report_is_not_terminated(self) -> None:
        """Record the current PID output format: JSON without a trailing newline.

        Line-based readers block until the app writes a newline or exits.
        """
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            chunk = await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            _, consumed = _leading_json_object(chunk)
            self.assertEqual(
                chunk[consumed : consumed + 1],
                b"",
                "the pid report is expected to arrive unterminated",
            )
