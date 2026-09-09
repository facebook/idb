# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""An application through its whole lifecycle, and the streaming launch that
holds one open and tails its output, against the companion's bundled
``ReplHost.app``."""

from __future__ import annotations

import json
from typing import Any

from .harness import IdbEndToEndTestCase

# The app is launched and reported over gRPC before it draws anything, but the
# report still crosses a companion, a simulator and a process spawn.
PID_REPORT_TIMEOUT_SECONDS = 120.0


def _leading_json_object(data: bytes) -> tuple[Any, int]:
    """The first JSON value in ``data`` and the offset just past it."""
    return json.JSONDecoder().raw_decode(data.decode(errors="replace"))


class ApplicationLifecycleTests(IdbEndToEndTestCase):
    async def test_install_launch_terminate_and_uninstall(self) -> None:
        bundle_id = await self.install_fixture_app()

        # simctl is the ground truth for what is installed; list-apps must agree.
        installed = await self.simctl.installed_bundle_ids()
        if installed is not None:
            self.assertIn(bundle_id, installed, "simctl does not see the installed app")
        app = (await self.installed_apps())[bundle_id]
        self.assertEqual(app["install_type"], "user")
        self.assertNotEqual(app["process_state"], "Running")

        pid_file = self.make_temporary_directory() / "pid"
        await self.idb("launch", "--pid-file", str(pid_file), bundle_id)
        # The pid file carries a JSON object, not a bare number.
        pid = json.loads(pid_file.read_text())["pid"]
        self.assertGreater(pid, 0)
        running = (await self.installed_apps())[bundle_id]
        self.assertEqual(running["process_state"], "Running")
        # list-apps spells the pid as a string.
        self.assertEqual(int(running["pid"]), pid)

        await self.idb("terminate", bundle_id)
        self.assertNotEqual(
            (await self.installed_apps())[bundle_id]["process_state"], "Running"
        )

        await self.idb("uninstall", bundle_id)
        self.assertNotIn(bundle_id, await self.installed_apps())
        installed = await self.simctl.installed_bundle_ids()
        if installed is not None:
            self.assertNotIn(
                bundle_id, installed, "simctl still sees the uninstalled app"
            )

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
    """``launch --wait-for``: the launch that stays attached to the app.

    This is how a test runner starts an app it intends to drive. The command
    does not return when the app is up -- it reports the app's pid, then keeps
    running, forwarding the app's stdout and stderr to its own, until it is
    asked to stop, at which point the app goes down with it. So what a caller
    depends on is the shape of the stream and the lifetime of the process, not
    an exit status.
    """

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
            # A launch that returned as soon as the app was up would have
            # exited by now; this one is meant to still be attached.
            await self.idb("ui", "button", "HOME", check=False)
            self.assertIsNone(
                launch.returncode,
                "launch --wait-for should stay attached while the app runs",
            )
            self.assertEqual(
                (await self.installed_apps())[self.bundle_id]["process_state"],
                "Running",
            )

        # Leaving the block stops the launch, which takes the app with it.
        self.assertNotEqual(
            (await self.installed_apps())[self.bundle_id]["process_state"],
            "Running",
            "stopping the launch should stop the app it was holding open",
        )

    async def test_the_pid_report_is_not_terminated(self) -> None:
        """The pid report is written to stdout with no delimiter after it.

        A caller reading the stream a line at a time therefore never sees the
        pid: the read blocks until the app itself happens to write a newline,
        which an app that logs nothing never does. Callers work around it by
        reading raw chunks and re-framing the report themselves.
        """
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            chunk = await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            _, consumed = _leading_json_object(chunk)
            # BUG: the report should be newline-terminated so that it is a
            # frame on its own -- flipped to assertEqual(remainder[:1], b"\n")
            # once the client terminates it.
            self.assertEqual(
                chunk[consumed : consumed + 1],
                b"",
                "the pid report is expected to arrive unterminated",
            )
