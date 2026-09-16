# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Verify guest service commands against the leased simulator's backing stores."""

from __future__ import annotations

import json
import plistlib
from typing import Any

from .harness import IdbEndToEndTestCase, NotReady, run, wait_until


class ServiceMutationTests(IdbEndToEndTestCase):
    async def probe_data(self, *arguments: str, stdin: bytes | None = None) -> bytes:
        completed = await run(
            self.simctl.argv(
                "spawn", self.udid, str(self.environment.service_probe), *arguments
            ),
            timeout=60.0,
            stdin=stdin,
        )
        if completed.returncode != 0:
            signature = await run(
                [
                    "codesign",
                    "--display",
                    "--verbose=4",
                    "--entitlements",
                    ":-",
                    str(self.environment.service_probe),
                ],
                timeout=30.0,
            )
            self.fail(
                f"probe {self.environment.service_probe} failed ({completed.returncode}): "
                f"{completed.error_text}\nsignature: {signature.text}\n{signature.error_text}"
            )
        return completed.stdout

    async def probe(
        self, *arguments: str, stdin: bytes | None = None
    ) -> dict[str, Any]:
        return plistlib.loads(await self.probe_data(*arguments, stdin=stdin))

    async def restore_network(self, service: str, snapshot: bytes) -> None:
        restored = await self.probe(service, "restore", stdin=snapshot)
        self.assertEqual(
            restored, plistlib.loads(snapshot), f"{service} state was not restored"
        )

    async def assert_network(self, service: str, expected: dict[str, Any]) -> None:
        self.assertEqual(
            await self.probe(service, "snapshot"),
            {"present": True, "value": expected},
        )
        self.assertEqual(json.loads((await self.guest(service, "list")).text), expected)

    async def test_dns_set_and_clear_update_the_dynamic_store(self) -> None:
        snapshot = await self.probe_data("dns", "snapshot")
        self.addAsyncCleanup(self.restore_network, "dns", snapshot)

        await self.guest("dns", "set", "192.0.2.1", "192.0.2.2")

        await self.assert_network(
            "dns", {"ServerAddresses": ["192.0.2.1", "192.0.2.2"]}
        )
        await self.guest("dns", "clear")
        await self.assert_network("dns", {})

    async def test_proxy_set_replaces_the_previous_type_and_clear_disables_it(
        self,
    ) -> None:
        snapshot = await self.probe_data("proxy", "snapshot")
        self.addAsyncCleanup(self.restore_network, "proxy", snapshot)

        await self.guest("proxy", "set", "192.0.2.3", "8123", "http")

        await self.assert_network(
            "proxy",
            {
                "HTTPEnable": 1,
                "HTTPProxy": "192.0.2.3",
                "HTTPPort": 8123,
                "HTTPSEnable": 1,
                "HTTPSProxy": "192.0.2.3",
                "HTTPSPort": 8123,
                "FTPPassive": 1,
                "ExceptionsList": ["*.local", "169.254/16"],
            },
        )
        await self.guest("proxy", "set", "192.0.2.4", "1080", "socks")
        await self.assert_network(
            "proxy",
            {
                "SOCKSEnable": 1,
                "SOCKSProxy": "192.0.2.4",
                "SOCKSPort": 1080,
                "FTPPassive": 1,
                "ExceptionsList": ["*.local", "169.254/16"],
            },
        )
        await self.guest("proxy", "clear")
        await self.assert_network("proxy", {"FTPPassive": 1})

    async def test_notification_approval_and_revocation_persist(self) -> None:
        bundle_id = await self.install_fixture_app()
        self.addAsyncCleanup(self.guest, "notifications", "revoke", bundle_id)

        await self.guest("notifications", "approve", bundle_id)

        await self.assert_notifications(bundle_id, True, 2)
        await self.guest("notifications", "revoke", bundle_id)
        await self.assert_notifications(bundle_id, False, 0)

    async def test_idb_notification_permissions_update_guest_settings(self) -> None:
        bundle_id = await self.install_fixture_app()
        self.addAsyncCleanup(self.idb, "revoke", bundle_id, "notification")

        approved = await self.idb("approve", bundle_id, "notification")

        self.assertEqual(approved.stdout, b"")
        await self.assert_notifications(bundle_id, True, 2)
        revoked = await self.idb("revoke", bundle_id, "notification")
        self.assertEqual(revoked.stdout, b"")
        await self.assert_notifications(bundle_id, False, 0)

    async def test_guest_accessibility_setting_write_reads_back(self) -> None:
        arguments = ("--setting", "reduce-motion")
        before = json.loads(
            (await self.guest("accessibility", "settings-get", *arguments)).text
        )
        self.assertEqual(before.get("ok"), True)
        self.assertIs(type(before.get("enabled")), bool)
        self.addAsyncCleanup(
            self.guest,
            "accessibility",
            "settings-set",
            *arguments,
            "--enabled",
            "true" if before["enabled"] else "false",
        )
        wanted = not before["enabled"]

        changed = json.loads(
            (
                await self.guest(
                    "accessibility",
                    "settings-set",
                    *arguments,
                    "--enabled",
                    "true" if wanted else "false",
                )
            ).text
        )

        self.assertEqual(changed, {"ok": True, "enabled": wanted})
        self.assertEqual(
            json.loads(
                (await self.guest("accessibility", "settings-get", *arguments)).text
            ),
            changed,
        )

    async def assert_notifications(
        self, bundle_id: str, enabled: bool, status: int
    ) -> None:
        expected = {
            "bundleID": bundle_id,
            "found": True,
            "allowsNotifications": enabled,
            "authorizationStatus": status,
            "showsInNotificationCenter": True,
            "showsInLockScreen": True,
        }

        async def check() -> dict[str, Any]:
            actual = json.loads(
                (await self.guest("notifications", "check", bundle_id)).text
            )
            if actual != expected:
                raise NotReady(
                    f"notification settings are {actual}, expected {expected}"
                )
            return actual

        self.assertEqual(
            await wait_until("notification settings", 30.0, check), expected
        )
