# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test app installation, launch, termination and removal using ReplHost.app."""

from __future__ import annotations

import contextlib
import functools
import http.server
import json
import shutil
import threading
from collections.abc import Iterator
from pathlib import Path
from typing import Any

from .harness import (
    FIXTURE_APP_BUNDLE_ID,
    HarnessError,
    IdbEndToEndTestCase,
    INSTALL_TIMEOUT_SECONDS,
    NotReady,
    wait_until,
)

PID_REPORT_TIMEOUT_SECONDS = 120.0

APP_STOP_TIMEOUT_SECONDS = 60.0


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
        await self.idb_expect_failure(
            "launch",
            "com.example.idb.not-installed",
            expected_error="isn't installed",
        )


@contextlib.contextmanager
def _serving(directory: Path) -> Iterator[str]:
    """Serve a directory over loopback HTTP, yielding its base URL."""
    handler = functools.partial(
        http.server.SimpleHTTPRequestHandler, directory=str(directory)
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        host, port = server.server_address[:2]
        yield f"http://{host}:{port}"
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


class ArchiveInstallTests(IdbEndToEndTestCase):
    def make_fixture_ipa(self, directory: Path) -> Path:
        staging = self.make_temporary_directory()
        fixture = self.environment.fixture_app
        shutil.copytree(fixture, staging / "Payload" / fixture.name, symlinks=True)
        archive = shutil.make_archive(
            str(staging / "fixture"), "zip", staging, "Payload"
        )
        return Path(shutil.move(archive, directory / "fixture.ipa"))

    async def test_installing_an_ipa(self) -> None:
        ipa = self.make_fixture_ipa(self.make_temporary_directory())
        self.addAsyncCleanup(self.uninstall_quietly, FIXTURE_APP_BUNDLE_ID)

        await self.idb("install", str(ipa), timeout=INSTALL_TIMEOUT_SECONDS)

        self.assertIn(FIXTURE_APP_BUNDLE_ID, await self.simctl.installed_bundle_ids())

    async def test_installing_an_ipa_keeps_the_app_for_debugging(self) -> None:
        ipa = self.make_fixture_ipa(self.make_temporary_directory())
        self.addAsyncCleanup(self.uninstall_quietly, FIXTURE_APP_BUNDLE_ID)

        await self.idb("install", str(ipa), timeout=INSTALL_TIMEOUT_SECONDS)

        # `debugserver start` and xctestrun placeholders resolve installed apps from here.
        persisted = (
            self.simctl.device_set_path
            / self.simctl.udid
            / "data/fbsimulatorcontrol/idb-applications"
            / FIXTURE_APP_BUNDLE_ID
            / self.environment.fixture_app.name
        )
        self.assertFalse(persisted.is_symlink())
        self.assertTrue((persisted / "Info.plist").exists())

    async def test_installing_an_ipa_from_a_url(self) -> None:
        served = self.make_temporary_directory()
        self.make_fixture_ipa(served)
        self.addAsyncCleanup(self.uninstall_quietly, FIXTURE_APP_BUNDLE_ID)

        with _serving(served) as base:
            await self.idb(
                "install", f"{base}/fixture.ipa", timeout=INSTALL_TIMEOUT_SECONDS
            )

        self.assertIn(FIXTURE_APP_BUNDLE_ID, await self.simctl.installed_bundle_ids())

    async def test_installing_from_a_missing_url_reports_the_http_status(self) -> None:
        with _serving(self.make_temporary_directory()) as base:
            await self.idb_expect_failure(
                "install",
                f"{base}/missing.ipa",
                expected_error="HTTP status 404",
                timeout=INSTALL_TIMEOUT_SECONDS,
            )


class LaunchOutputTests(IdbEndToEndTestCase):
    """Check PID output and app lifetime for launch --wait-for."""

    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.bundle_id = await self.install_fixture_app()

    async def test_launch_wait_for_reports_pid_on_stdout(self) -> None:
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            chunk = await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            report, consumed = json.JSONDecoder().raw_decode(
                chunk.decode(errors="replace")
            )
            self.assertIsInstance(report, dict)
            pid = report["pid"]
            self.assertGreater(pid, 0)
            # The report is newline-terminated, so a line-based reader finds it
            # without waiting on the app's own output to supply a delimiter.
            self.assertEqual(chunk[consumed : consumed + 1], b"\n")

            running = (await self.installed_apps())[self.bundle_id]
            self.assertEqual(running["process_state"], "Running")
            self.assertEqual(int(running["pid"]), pid)

    async def test_stopping_launch_wait_for_terminates_the_app(self) -> None:
        async with self.idb_process("launch", "--wait-for", self.bundle_id) as launch:
            await launch.read_some(PID_REPORT_TIMEOUT_SECONDS)
            # Background the app while keeping the launch command attached.
            await self.idb("ui", "button", "HOME", check=False)
            self.assertIsNone(
                launch.returncode,
                "launch --wait-for exited while the app was still running",
            )
            self.assertEqual(
                (await self.installed_apps())[self.bundle_id]["process_state"],
                "Running",
            )

        # App termination may finish after the launch command exits.
        await self.wait_for_app_to_stop()

    async def wait_for_app_to_stop(self) -> None:
        async def stopped() -> None:
            app = (await self.installed_apps())[self.bundle_id]
            if app["process_state"] == "Running":
                raise NotReady("list-apps still reports it running")

        await self.wait_or_fail(
            "App still running after launch --wait-for exited",
            APP_STOP_TIMEOUT_SECONDS,
            stopped,
        )
