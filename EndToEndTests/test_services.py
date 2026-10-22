# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Read and write the simulator's backing stores through guest services."""

from __future__ import annotations

import base64
import json
import plistlib
import uuid
from typing import Any

from .harness import (
    GuestRPC,
    IdbEndToEndTestCase,
    NotReady,
    reported_answers,
    run,
    tagged_answers,
    wait_until,
)

NEWS_BUNDLE_ID = "com.apple.news"
NOTIFICATION_TITLE = "Breaking"
NOTIFICATION_PAYLOAD = json.dumps(
    {
        "aps": {
            "alert": {
                "title": NOTIFICATION_TITLE,
                "body": "idb delivered this without the app running.",
            }
        }
    }
)
NOTIFICATION_STORE_TIMEOUT_SECONDS = 300.0
# A list can take over 30s, when the system doesn't answer idb and it reads
# the store instead, so a wait for the list to change allows for a few.
NOTIFICATION_LIST_TIMEOUT_SECONDS = 120.0


def _retained_notifications(text: str) -> list[tuple[str, str]]:
    """The identifier and title of each notification the system still holds."""
    held = []
    for line in text.splitlines():
        fields = [field.strip().strip('"') for field in line.split("|")]
        if len(fields) >= 3:
            held.append((fields[1], fields[2]))
    return held


class ServiceTests(IdbEndToEndTestCase):
    async def test_guest_health_list_reports_no_records_for_a_new_app(self) -> None:
        bundle_id = await self.install_fixture_app()
        listed = json.loads((await self.guest("health", "list", bundle_id)).stdout)
        self.assertEqual(
            listed,
            {
                "action": "list",
                "bundleID": bundle_id,
                "ok": True,
                "records": [],
            },
        )
        self.assertIs(type(listed["ok"]), bool)

    async def test_guest_rpc_answers_reads_as_the_verbs_do(self) -> None:
        bundle_id = await self.install_fixture_app()
        cases = [
            (
                {"health": {"action": {"list": {"bundleID": bundle_id}}}},
                ("health", "list", bundle_id),
            ),
            ({"dns": {"action": {"list": {}}}}, ("dns", "list")),
            ({"proxy": {"action": {"list": {}}}}, ("proxy", "list")),
            (
                {
                    "accessibility": {
                        "action": {"deviceSettingRead": {"setting": "reduce-motion"}}
                    }
                },
                ("accessibility", "settings-get", "--setting", "reduce-motion"),
            ),
        ]
        for persistent in (False, True):
            with self.subTest(persistent=persistent):
                async with GuestRPC(self, persistent=persistent) as rpc:
                    for command, arguments in cases:
                        with self.subTest(command=command):
                            expected = json.loads((await self.guest(*arguments)).stdout)
                            result = await rpc.send_result(command)
                            # An accessibility answer has a field of its own; every
                            # other service answers in `answers`.
                            if "accessibility" in command:
                                answer = reported_answers(result)[0]
                            else:
                                answer, expected = reported_answers(result), [expected]
                            # Compared as JSON, where `1` and `true` differ.
                            self.assertEqual(
                                json.dumps(answer, sort_keys=True),
                                json.dumps(expected, sort_keys=True),
                            )

    async def test_guest_rpc_writes_network_and_notification_state(self) -> None:
        for service in ("dns", "proxy"):
            snapshot = await self.store_data("snapshot", service)
            self.addAsyncCleanup(self.restore_network, service, snapshot)
        bundle_id = await self.install_fixture_app()
        self.addAsyncCleanup(self.guest, "notifications", "revoke", bundle_id)
        for persistent in (False, True):
            with self.subTest(persistent=persistent):
                async with GuestRPC(self, persistent=persistent) as rpc:
                    self.assertEqual(
                        await rpc.send(
                            {"dns": {"action": {"set": {"servers": ["192.0.2.10"]}}}}
                        ),
                        [],
                    )
                    await self.assert_network(
                        "dns", {"ServerAddresses": ["192.0.2.10"]}
                    )
                    self.assertEqual(
                        await rpc.send({"dns": {"action": {"clear": {}}}}), []
                    )
                    await self.assert_network("dns", {})
                    self.assertEqual(
                        await rpc.send(
                            {
                                "proxy": {
                                    "action": {
                                        "set": {
                                            "host": "192.0.2.11",
                                            "port": 1080,
                                            "kind": "socks",
                                        }
                                    }
                                }
                            }
                        ),
                        [],
                    )
                    await self.assert_network(
                        "proxy",
                        {
                            "SOCKSEnable": 1,
                            "SOCKSProxy": "192.0.2.11",
                            "SOCKSPort": 1080,
                            "FTPPassive": 1,
                            "ExceptionsList": ["*.local", "169.254/16"],
                        },
                    )
                    self.assertEqual(
                        await rpc.send({"proxy": {"action": {"clear": {}}}}), []
                    )
                    await self.assert_network("proxy", {"FTPPassive": 1})
                    for action, enabled, status in (
                        ("approve", True, 2),
                        ("revoke", False, 0),
                    ):
                        self.assertEqual(
                            await rpc.send(
                                {
                                    "notifications": {
                                        "action": {action: {"bundleID": bundle_id}}
                                    }
                                }
                            ),
                            [],
                        )
                        await self.assert_notifications(bundle_id, enabled, status)

    async def test_guest_rpc_restores_dynamic_store_snapshots_losslessly(self) -> None:
        key = f"State:/idb-tests/{uuid.uuid4()}"
        original = await self.store_data("snapshot", key)
        self.addAsyncCleanup(self.restore_network, key, original)
        snapshots = [
            {
                "present": True,
                "value": {"bytes": b"\x00\xff", "items": [True, 1, "text"]},
            },
            {"present": False},
        ]
        for persistent in (False, True):
            with self.subTest(persistent=persistent):
                async with GuestRPC(self, persistent=persistent) as rpc:
                    for snapshot in snapshots:
                        data = base64.b64encode(plistlib.dumps(snapshot)).decode()
                        commands = [
                            {"restore": {"key": key, "snapshot": data}},
                            {"snapshot": {"key": key}},
                        ]
                        for command in commands:
                            result = await rpc.send_result(
                                {"dynamicStore": {"action": command}}
                            )
                            ((kind, encoded_snapshot),) = tagged_answers(result)
                            self.assertEqual(kind, "dynamicStoreSnapshot")
                            encoded = base64.b64decode(encoded_snapshot, validate=True)
                            self.assertTrue(encoded.startswith(b"bplist00"))
                            self.assertEqual(plistlib.loads(encoded), snapshot)
                            self.assertEqual(
                                await self.store("snapshot", key), snapshot
                            )

    async def store_data(self, *arguments: str, stdin: bytes | None = None) -> bytes:
        completed = await run(
            self.simctl.argv(
                "spawn",
                self.udid,
                str(self.environment.guest_binary),
                "dynamic-store",
                *arguments,
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
                    str(self.environment.guest_binary),
                ],
                timeout=30.0,
            )
            self.fail(
                f"guest dynamic-store {arguments} failed ({completed.returncode}): "
                f"{completed.error_text}\nsignature: {signature.text}\n{signature.error_text}"
            )
        return completed.stdout

    async def store(
        self, *arguments: str, stdin: bytes | None = None
    ) -> dict[str, Any]:
        return plistlib.loads(await self.store_data(*arguments, stdin=stdin))

    async def restore_network(self, service: str, snapshot: bytes) -> None:
        restored = await self.store("restore", service, stdin=snapshot)
        self.assertEqual(
            restored, plistlib.loads(snapshot), f"{service} state was not restored"
        )

    async def assert_network(self, service: str, expected: dict[str, Any]) -> None:
        self.assertEqual(
            await self.store("snapshot", service),
            {"present": True, "value": expected},
        )
        self.assertEqual(json.loads((await self.guest(service, "list")).text), expected)

    async def test_guest_proxy_set_replaces_the_previous_type(
        self,
    ) -> None:
        snapshot = await self.store_data("snapshot", "proxy")
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

    async def test_approve_and_revoke_notification_update_the_app_settings(
        self,
    ) -> None:
        bundle_id = await self.install_fixture_app()
        self.addAsyncCleanup(self.idb, "revoke", bundle_id, "notification")

        approved = await self.idb("approve", bundle_id, "notification")

        self.assertEqual(approved.stdout, b"")
        await self.assert_notifications(bundle_id, True, 2)
        revoked = await self.idb("revoke", bundle_id, "notification")
        self.assertEqual(revoked.stdout, b"")
        await self.assert_notifications(bundle_id, False, 0)

    async def test_send_notification_is_held_for_an_app_that_is_not_running(
        self,
    ) -> None:
        self.addAsyncCleanup(self.setup_terminate_quietly, NEWS_BUNDLE_ID)
        self.addAsyncCleanup(
            self.setup_idb, "notification", "clear", NEWS_BUNDLE_ID, check=False
        )
        await self.setup_terminate_quietly(NEWS_BUNDLE_ID)
        # The first push after an erase waits, for minutes at worst, on the
        # system building its notification store. Sent before the permission
        # is granted, this one is refused and stores nothing.
        await self.setup_idb(
            "send-notification",
            NEWS_BUNDLE_ID,
            NOTIFICATION_PAYLOAD,
            check=False,
            timeout=NOTIFICATION_STORE_TIMEOUT_SECONDS,
        )
        await self.setup_idb("approve", NEWS_BUNDLE_ID, "notification")
        listed = await self.setup_idb("notification", "list", NEWS_BUNDLE_ID)
        before = {identifier for identifier, _ in _retained_notifications(listed.text)}

        await self.idb("send-notification", NEWS_BUNDLE_ID, NOTIFICATION_PAYLOAD)

        async def held() -> None:
            completed = await self.idb("notification", "list", NEWS_BUNDLE_ID)
            if not [
                identifier
                for identifier, title in _retained_notifications(completed.text)
                if title == NOTIFICATION_TITLE and identifier not in before
            ]:
                raise NotReady(f"{NOTIFICATION_TITLE!r} is not held yet")

        await self.wait_or_fail(
            f"The system did not hold {NOTIFICATION_TITLE!r} for {NEWS_BUNDLE_ID}",
            NOTIFICATION_LIST_TIMEOUT_SECONDS,
            held,
        )

    async def test_guest_accessibility_settings_set_reads_back(self) -> None:
        arguments = ("--setting", "reduce-motion")
        read = json.loads(
            (await self.guest("accessibility", "settings-get", *arguments)).text
        )
        self.assertEqual(list(read), ["setting"])
        before = read["setting"]["response"]
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

        self.assertEqual(changed, {"setting": {"response": {"enabled": wanted}}})
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
