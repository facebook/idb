# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""What idb asks the simulator to do on an app's behalf: open a URL, and grant
or take back a privacy permission.

Neither command reports what it did, so both are read back from the simulator
itself -- the URL's handler from `launchctl` in the guest, the permission from
the simulator's own TCC database on the host. An exit code would say only that
idb sent the request.
"""

from __future__ import annotations

import sqlite3
from contextlib import closing
from pathlib import Path

from .harness import HarnessError, IdbEndToEndTestCase, NotReady, wait_until

# Nothing is fetched -- the runner has no network. Opening the URL only has to
# reach the app registered for its scheme.
URL = "https://example.com"
SAFARI_BUNDLE_ID = "com.apple.mobilesafari"

# Launching Safari from cold is the slow part; the read itself is immediate.
RUNNING_TIMEOUT_SECONDS = 60.0

# The privacy database the simulator itself consults, and the value it stores
# for a granted permission.
TCC_DATABASE = Path("Library") / "TCC" / "TCC.db"
TCC_ALLOWED = 2

PHOTOS_SERVICE = "kTCCServicePhotos"
CONTACTS_SERVICE = "kTCCServiceAddressBook"


class OpenUrlTests(IdbEndToEndTestCase):
    async def test_opening_a_url_launches_the_app_that_handles_it(self) -> None:
        # Safari may have been left running by an earlier test, in which case
        # finding it running afterwards would prove nothing.
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
    async def test_a_permission_is_granted_and_taken_back_one_at_a_time(self) -> None:
        bundle_id = await self.install_fixture_app()
        # Nothing resets privacy between tests, so this asserts the run's own
        # starting point as well: an install after an earlier run's uninstall
        # has been granted nothing, which is what makes the run repeatable
        # despite the grants it leaves behind.
        self.assertEqual(
            self.granted_permissions(bundle_id),
            {},
            "a freshly installed app has been granted nothing",
        )

        await self.idb("approve", bundle_id, "photos", "contacts")

        self.assertEqual(
            self.granted_permissions(bundle_id),
            {PHOTOS_SERVICE: TCC_ALLOWED, CONTACTS_SERVICE: TCC_ALLOWED},
        )

        await self.idb("revoke", bundle_id, "photos")

        self.assertEqual(
            self.granted_permissions(bundle_id),
            {CONTACTS_SERVICE: TCC_ALLOWED},
            "revoke should take back only the permission it names",
        )

    def granted_permissions(self, bundle_id: str) -> dict[str, int]:
        """What the simulator's privacy database says this app may do."""
        database = self.simctl.device_set_path / self.udid / "data" / TCC_DATABASE
        if not database.is_file():
            raise HarnessError(
                f"the simulator has no privacy database at {database}, so there "
                f"is no ground truth to check against"
            )
        # sqlite3's own context manager ends the transaction rather than the
        # connection, and this reads the file the simulator is writing to.
        with closing(
            sqlite3.connect(f"file:{database}?mode=ro", uri=True)
        ) as connection:
            rows = connection.execute(
                "select service, auth_value from access where client = ?",
                (bundle_id,),
            ).fetchall()
        return dict(rows)
