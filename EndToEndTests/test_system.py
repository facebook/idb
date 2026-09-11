# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Check URL handling with launchctl and permissions in the simulator TCC database."""

from __future__ import annotations

import sqlite3
from contextlib import closing
from pathlib import Path

from .harness import HarnessError, IdbEndToEndTestCase, NotReady, wait_until

# Only Safari launch is checked; page loading does not need to succeed.
URL = "https://example.com"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"

RUNNING_TIMEOUT_SECONDS = 60.0

TCC_DATABASE = Path("Library") / "TCC" / "TCC.db"
TCC_ALLOWED = 2

PHOTOS_SERVICE = "kTCCServicePhotos"
CONTACTS_SERVICE = "kTCCServiceAddressBook"


class OpenUrlTests(IdbEndToEndTestCase):
    async def test_opening_a_url_launches_the_app_that_handles_it(self) -> None:
        # Start with Safari stopped so the test can detect the URL launching it.
        await self.terminate_quietly(SAFARI_BUNDLE_ID)
        await self.wait_until_running(SAFARI_BUNDLE_ID, False)
        self.addAsyncCleanup(self.terminate_quietly, SAFARI_BUNDLE_ID)

        await self.idb("open", URL)

        await self.wait_until_running(SAFARI_BUNDLE_ID, True)

    async def wait_until_running(self, bundle_id: str, running: bool) -> None:
        async def check() -> None:
            listed = bundle_id in await self.simctl.running_bundle_ids()
            if listed != running:
                raise NotReady(
                    "launchctl still lists it"
                    if listed
                    else "launchctl does not list it"
                )

        state = "running" if running else "stopped"
        try:
            await wait_until(
                f"{bundle_id} was not {state}", RUNNING_TIMEOUT_SECONDS, check
            )
        except HarnessError as error:
            self.fail(str(error))


class PermissionTests(IdbEndToEndTestCase):
    async def test_revoke_removes_only_the_requested_permission(self) -> None:
        bundle_id = await self.install_fixture_app()
        # Uninstall cleanup should remove permissions from previous runs.
        self.assertEqual(
            self.permission_records(bundle_id),
            {},
            "a freshly installed app has been granted nothing",
        )

        await self.idb("approve", bundle_id, "photos", "contacts")

        self.assertEqual(
            self.permission_records(bundle_id),
            {PHOTOS_SERVICE: TCC_ALLOWED, CONTACTS_SERVICE: TCC_ALLOWED},
        )

        await self.idb("revoke", bundle_id, "photos")

        self.assertEqual(
            self.permission_records(bundle_id),
            {CONTACTS_SERVICE: TCC_ALLOWED},
            "revoking photos should leave contacts permission unchanged",
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
