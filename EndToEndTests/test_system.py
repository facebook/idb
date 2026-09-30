# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Open URLs, and approve and revoke the permissions apps ask for."""

from __future__ import annotations

import sqlite3
from contextlib import closing
from pathlib import Path
from typing import Any

from .harness import (
    AppState,
    HarnessError,
    IdbEndToEndTestCase,
    NotReady,
    SuiteCapability,
)

# Only Safari launch is checked; page loading does not need to succeed.
URL = "https://example.com"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"

TCC_DATABASE = Path("Library") / "TCC" / "TCC.db"
TCC_ALLOWED = 2

PHOTOS_SERVICE = "kTCCServicePhotos"
CONTACTS_SERVICE = "kTCCServiceAddressBook"

PRIVACY_SERVICES = ("camera", "microphone", "photos", "contacts")
IDLE_MARKER = "privacy-result-idle"
# SpringBoard presents the prompt, so none of it belongs to the app. Its shape
# varies by service -- Photos offers "Select Photos" and "Allow Full Access"
# where camera offers a plain "Allow" -- and the deny button is the only control
# common to every shape, so it stands for the prompt being up. The apostrophe is
# typographic; a build that spells it differently fails with the labels it saw.
DENY_BUTTON = "Don’t Allow"
PROMPT_TIMEOUT_SECONDS = 60.0

PERMISSION_TEST_CAPABILITIES = {
    "test_approve_removes_the_system_prompt": (
        SuiteCapability.ACCESSIBILITY_INTERACTION
    ),
    "test_revoke_removes_only_the_requested_permission": (
        SuiteCapability.COMPANION_PROCESS
    ),
}


class OpenUrlTests(IdbEndToEndTestCase):
    async def test_opening_a_url_launches_the_app_that_handles_it(self) -> None:
        # Safari starts stopped, so its launch can only come from the URL.
        await self.setup_terminate_quietly(SAFARI_BUNDLE_ID)
        await self.wait_for_app(SAFARI_BUNDLE_ID, AppState.STOPPED)
        self.addAsyncCleanup(self.setup_terminate_quietly, SAFARI_BUNDLE_ID)

        await self.idb("open", URL)

        await self.wait_for_app(SAFARI_BUNDLE_ID, AppState.RUNNING)


class PermissionTests(IdbEndToEndTestCase):
    capabilities = PERMISSION_TEST_CAPABILITIES

    async def test_approve_removes_the_system_prompt(self) -> None:
        """What approving a service buys: the app stops having to ask for it.

        TCC authorization is scoped to the requesting client, so the approval is
        only observable from inside the app. Asking for it is what makes the
        difference visible -- unapproved, the request reaches the user as a
        system prompt; approved, it is answered without one.
        """
        await self.setup_deny_permission_prompts()
        bundle_id = await self.install_fixture_app()
        # A prompt left up by a failure here would cover every later test.
        self.addAsyncCleanup(self.setup_deny_permission_prompts)

        for service in PRIVACY_SERVICES:
            await self.relaunch(bundle_id)
            await self.request(service)
            await self.wait_for_system_prompt(service)
            await self.deny_system_prompt()

        await self.approve(bundle_id, *PRIVACY_SERVICES)

        for service in PRIVACY_SERVICES:
            await self.relaunch(bundle_id)
            await self.request(service)
            # Photos reports full authorization, not a limited selection.
            await self.wait_for_marker(f"privacy-result-{service}-authorized")
            self.assertFalse(
                await self.system_prompt_showing(),
                f"{service} was approved beforehand, so the app must not ask for it",
            )

    async def approve(self, bundle_id: str, *services: str) -> None:
        """Approve the services, and revoke them again when the test ends.

        Uninstalling does not reliably take the grants away: tccd drops them
        seconds later, and not at all if the app has been reinstalled by then,
        so the next test's fresh install would inherit them.
        """
        self.addAsyncCleanup(self.idb, "revoke", bundle_id, *services, check=False)
        await self.idb("approve", bundle_id, *services)

    async def relaunch(self, bundle_id: str) -> None:
        await self.idb("terminate", bundle_id, check=False)
        await self.idb("launch", bundle_id)
        await self.wait_for_marker(IDLE_MARKER)

    async def deny_system_prompt(self) -> None:
        """Answer the prompt, so the baseline leaves the service unapproved.

        Terminating the app does not take the prompt down: SpringBoard owns it
        and holds it across a relaunch. Denying also makes the approval that
        follows overturn a recorded denial rather than an undecided service.
        """
        await self.idb("ui", "tap", DENY_BUTTON, "--match-key", "AXLabel")

    async def request(self, service: str) -> None:
        await self.idb("ui", "tap", f"request-{service}", "--match-key", "AXUniqueId")

    async def elements(self) -> list[dict[str, Any]]:
        return await self.idb_json("ui", "describe-all")

    async def button_labels(self) -> list[str]:
        return [
            element.get("AXLabel")
            for element in await self.elements()
            if element.get("role") == "AXButton"
        ]

    async def system_prompt_showing(self) -> bool:
        return DENY_BUTTON in await self.button_labels()

    async def wait_for_system_prompt(self, service: str) -> None:
        async def check() -> None:
            labels = await self.button_labels()
            if DENY_BUTTON not in labels:
                raise NotReady(f"the buttons on screen are {labels}")

        await self.wait_or_fail(
            f"requesting {service} raised no system prompt",
            PROMPT_TIMEOUT_SECONDS,
            check,
        )
        self.recording.event("system_prompt", service=service)

    async def wait_for_marker(self, marker: str) -> None:
        async def check() -> None:
            identifiers = [
                element.get("AXUniqueId") for element in await self.elements()
            ]
            if marker not in identifiers:
                raise NotReady(f"the app reports {[i for i in identifiers if i]}")

        await self.wait_or_fail(
            f"{marker} did not appear", PROMPT_TIMEOUT_SECONDS, check
        )
        self.recording.event("app_marker", marker=marker)

    async def test_revoke_removes_only_the_requested_permission(self) -> None:
        bundle_id = await self.install_fixture_app()
        self.assertEqual(
            self.permission_records(bundle_id),
            {},
            "a freshly installed app has been granted nothing",
        )

        await self.approve(bundle_id, "photos", "contacts")

        self.assertEqual(
            self.permission_records(bundle_id),
            {PHOTOS_SERVICE: TCC_ALLOWED, CONTACTS_SERVICE: TCC_ALLOWED},
        )

        await self.idb("revoke", bundle_id, "photos")

        self.assertEqual(
            self.permission_records(bundle_id),
            {CONTACTS_SERVICE: TCC_ALLOWED},
            "revoking photos changed the contacts permission",
        )

    def permission_records(self, bundle_id: str) -> dict[str, int]:
        """Read permission records from the simulator privacy database."""
        database = self.simctl.device_set_path / self.udid / "data" / TCC_DATABASE
        if not database.is_file():
            raise HarnessError(f"Simulator privacy database not found: {database}")
        # closing() closes the connection; sqlite3's context manager only ends the transaction.
        with closing(
            sqlite3.connect(f"file:{database}?mode=ro", uri=True)
        ) as connection:
            rows = connection.execute(
                "select service, auth_value from access where client = ?",
                (bundle_id,),
            ).fetchall()
        return dict(rows)
