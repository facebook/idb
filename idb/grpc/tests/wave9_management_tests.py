#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import logging
import signal
import tempfile
from collections.abc import AsyncGenerator
from contextlib import asynccontextmanager
from pathlib import Path
from unittest.mock import AsyncMock, call, MagicMock, patch

from idb.common.companion_set import CompanionSet
from idb.common.types import (
    CompanionInfo,
    DomainSocketAddress,
    IdbException,
    TargetDescription,
    TargetType,
    TCPAddress,
)
from idb.grpc import management
from idb.grpc.management import ClientManager
from idb.utils.testing import TestCase


_PENDING_MANAGEMENT_CORRECTIONS: dict[str, str] = {
    "compare_and_remove": "pending",
    "deduplicate_pids": "pending",
    "pid_identity_validation": "pending",
    "typed_signal_failure": "pending",
}


@asynccontextmanager
async def _client_context(client: object) -> AsyncGenerator[object, None]:
    yield client


class _FailingContext:
    def __init__(self, error: Exception) -> None:
        self.error = error

    async def __aenter__(self) -> object:
        raise self.error

    async def __aexit__(self, *_args: object) -> bool:
        return False


def _companion(
    udid: str,
    address: TCPAddress | DomainSocketAddress | None = None,
    pid: int | None = None,
) -> CompanionInfo:
    return CompanionInfo(
        udid=udid,
        address=address or DomainSocketAddress(path=f"/tmp/{udid}.sock"),
        is_local=isinstance(address, DomainSocketAddress) or address is None,
        pid=pid,
    )


def _target(
    udid: str,
    *,
    target_type: TargetType = TargetType.DEVICE,
    companion_info: CompanionInfo | None = None,
) -> TargetDescription:
    return TargetDescription(
        udid=udid,
        name=udid,
        state=None,
        target_type=target_type,
        os_version=None,
        architecture=None,
        companion_info=companion_info,
        screen_dimensions=None,
    )


class Wave9ManagementTests(TestCase):
    def setUp(self) -> None:
        super().setUp()
        self._temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary_directory.cleanup)
        self.logger = MagicMock(spec=logging.Logger)
        self.manager = ClientManager(logger=self.logger)
        self.manager._companion_set = CompanionSet(
            logger=self.logger,
            state_file_path=str(
                Path(self._temporary_directory.name) / "companions.json"
            ),
        )

    async def _set_companions(self, *companions: CompanionInfo) -> None:
        await self.manager._companion_set.clear()
        for companion in companions:
            await self.manager._companion_set.add_companion(companion)

    async def _stored_companions(self) -> list[CompanionInfo]:
        return await self.manager._companion_set.get_companions()

    async def test_registry_selection_existing_spawn_sole_none_and_multiple(
        self,
    ) -> None:
        client = object()
        existing = _companion("existing")
        spawned = _companion("spawned")
        sole = _companion("sole")
        first = _companion("first")
        second = _companion("second")

        with (
            patch.object(
                management.Client,
                "build",
                side_effect=lambda **_kwargs: _client_context(client),
            ) as build,
            patch.object(
                self.manager,
                "_spawn_companion_server",
                new=AsyncMock(return_value=spawned),
            ) as spawn,
        ):
            await self._set_companions(existing)
            async with self.manager.from_udid("existing") as actual:
                self.assertIs(actual, client)
            build.assert_called_once_with(
                address=existing.address,
                logger=self.logger,
            )
            spawn.assert_not_awaited()

            build.reset_mock()
            async with self.manager.from_udid("spawned") as actual:
                self.assertIs(actual, client)
            spawn.assert_awaited_once_with(udid="spawned")
            build.assert_called_once_with(
                address=spawned.address,
                logger=self.logger,
            )

            build.reset_mock()
            spawn.reset_mock()
            await self._set_companions(sole)
            async with self.manager.from_udid(None) as actual:
                self.assertIs(actual, client)
            build.assert_called_once_with(address=sole.address, logger=self.logger)
            spawn.assert_not_awaited()

            build.reset_mock()
            await self._set_companions()
            with self.assertRaisesRegex(
                IdbException, "No udid provided.*no companions"
            ):
                async with self.manager.from_udid(None):
                    self.fail("an empty registry must not yield a client")
            build.assert_not_called()

            await self._set_companions(first, second)
            with self.assertRaisesRegex(IdbException, "multiple companions"):
                async with self.manager.from_udid(None):
                    self.fail("an ambiguous registry must not yield a client")
            build.assert_not_called()

    async def test_connect_host_handshake_udid_spawn_add_replace_and_failure_atomicity(
        self,
    ) -> None:
        destination = TCPAddress(host="remote.example", port=10882)
        old = _companion(
            "handshake-udid",
            TCPAddress(host="old.example", port=1),
        )
        incoming = _companion("handshake-udid", destination)
        await self._set_companions(old)
        client = MagicMock()
        client.companion = incoming
        real_add = self.manager._companion_set.add_companion
        with (
            patch.object(
                management.Client,
                "build",
                return_value=_client_context(client),
            ) as build,
            patch.object(
                self.manager._companion_set,
                "add_companion",
                new=AsyncMock(wraps=real_add),
            ) as add,
        ):
            actual = await self.manager.connect(destination)
        self.assertIs(actual, incoming)
        self.assertEqual(actual.udid, "handshake-udid")
        self.assertEqual(actual.address, destination)
        build.assert_called_once_with(
            address=destination,
            logger=self.logger,
        )
        add.assert_awaited_once_with(incoming)
        self.assertEqual(await self._stored_companions(), [incoming])

        await self._set_companions()
        local = MagicMock()
        local.spawn_domain_sock_server = AsyncMock(return_value=MagicMock(pid=73))
        self.manager._companion = local
        real_add = self.manager._companion_set.add_companion
        with (
            patch.object(
                management,
                "_local_target_type",
                new=AsyncMock(return_value=TargetType.SIMULATOR),
            ),
            patch.object(
                management,
                "_check_domain_socket_is_bound",
                new=AsyncMock(return_value=False),
            ),
            patch.object(
                self.manager._companion_set,
                "add_companion",
                new=AsyncMock(wraps=real_add),
            ) as add,
        ):
            spawned = await self.manager.connect("spawned")
        self.assertEqual(spawned.udid, "spawned")
        self.assertEqual(spawned.pid, 73)
        add.assert_awaited_once_with(spawned)
        self.assertEqual(await self._stored_companions(), [spawned])

        before_add = _companion("before-add")
        await self._set_companions(before_add)
        real_add = self.manager._companion_set.add_companion
        add = AsyncMock(wraps=real_add)
        # This proves only pre-add atomicity: handshake failure occurs before
        # add, leaving the prior registry state unchanged.
        with (
            patch.object(self.manager._companion_set, "add_companion", add),
            patch.object(
                management.Client,
                "build",
                return_value=_FailingContext(IdbException("handshake failed")),
            ),
            self.assertRaisesRegex(IdbException, "handshake failed"),
        ):
            await self.manager.connect(TCPAddress(host="bad.example", port=9))
        add.assert_not_awaited()
        self.assertEqual(await self._stored_companions(), [before_add])

        await self._set_companions(before_add)
        local.spawn_domain_sock_server = AsyncMock(
            side_effect=IdbException("spawn failed")
        )
        real_add = self.manager._companion_set.add_companion
        add = AsyncMock(wraps=real_add)
        # This likewise claims only that the spawn failure precedes add.
        with (
            patch.object(
                management,
                "_local_target_type",
                new=AsyncMock(return_value=TargetType.SIMULATOR),
            ),
            patch.object(
                management,
                "_check_domain_socket_is_bound",
                new=AsyncMock(return_value=False),
            ),
            patch.object(self.manager._companion_set, "add_companion", add),
            self.assertRaisesRegex(IdbException, "spawn failed"),
        ):
            await self.manager.connect("missing")
        add.assert_not_awaited()
        self.assertEqual(await self._stored_companions(), [before_add])

    async def test_disconnect_matches_udid_tcp_and_domain_socket(self) -> None:
        by_udid = _companion("by-udid", TCPAddress(host="one", port=1))
        by_tcp = _companion("by-tcp", TCPAddress(host="two", port=2))
        by_domain = _companion(
            "by-domain",
            DomainSocketAddress(path="/tmp/by-domain.sock"),
        )
        untouched = _companion(
            "untouched",
            DomainSocketAddress(path="/tmp/untouched.sock"),
        )
        await self._set_companions(by_udid, by_tcp, by_domain, untouched)

        self.assertIsNone(await self.manager.disconnect("by-udid"))
        self.assertEqual(
            await self._stored_companions(),
            [by_domain, by_tcp, untouched],
        )
        self.assertIsNone(await self.manager.disconnect(by_tcp.address))
        self.assertEqual(await self._stored_companions(), [by_domain, untouched])
        self.assertIsNone(await self.manager.disconnect(by_domain.address))
        self.assertEqual(await self._stored_companions(), [untouched])

    async def test_kill_clears_before_signals_and_ignores_null_pid(self) -> None:
        await self._set_companions(
            _companion("a", pid=41),
            _companion("b", pid=None),
            _companion("c", pid=41),
            _companion("d", pid=42),
        )
        events: list[object] = []
        real_clear = self.manager._companion_set.clear

        async def clear() -> list[CompanionInfo]:
            cleared = await real_clear()
            events.append("clear-complete")
            return cleared

        def kill(pid: int, sig: signal.Signals) -> None:
            events.append((pid, sig))

        with (
            patch.object(
                self.manager._companion_set,
                "clear",
                new=AsyncMock(side_effect=clear),
            ) as clear_mock,
            patch.object(management.os, "kill", side_effect=kill) as kill_mock,
        ):
            await self.manager.kill()

        clear_mock.assert_awaited_once_with()
        self.assertEqual(await self._stored_companions(), [])
        self.assertEqual(
            events,
            [
                "clear-complete",
                (41, signal.SIGKILL),
                (41, signal.SIGKILL),
                (42, signal.SIGKILL),
            ],
        )
        self.assertEqual(
            kill_mock.call_args_list,
            [
                call(41, signal.SIGKILL),
                call(41, signal.SIGKILL),
                call(42, signal.SIGKILL),
            ],
        )
        self.assertEqual(
            {
                name: _PENDING_MANAGEMENT_CORRECTIONS[name]
                for name in (
                    "deduplicate_pids",
                    "pid_identity_validation",
                    "typed_signal_failure",
                )
            },
            {
                "deduplicate_pids": "pending",
                "pid_identity_validation": "pending",
                "typed_signal_failure": "pending",
            },
        )

    async def test_list_targets_merges_local_connected_and_prunes_by_policy(
        self,
    ) -> None:
        local_b = _target("b")
        local_a = _target("a")
        info_a = _companion("a", TCPAddress(host="a", port=1))
        info_c = _companion("c", TCPAddress(host="c", port=3))
        dead = _companion("dead", TCPAddress(host="dead", port=4))
        connected_a = _target("a", companion_info=info_a)
        connected_c = _target(
            "c",
            target_type=TargetType.SIMULATOR,
            companion_info=info_c,
        )
        behaviors: dict[object, TargetDescription | Exception] = {
            info_a.address: connected_a,
            info_c.address: connected_c,
            dead.address: IdbException("dead"),
        }
        local = MagicMock()
        local.list_targets = AsyncMock(return_value=[local_b, local_a])
        self.manager._companion = local

        def build(*, address: object, logger: object):
            self.assertIs(logger, self.logger)
            client = MagicMock()
            behavior = behaviors[address]
            client.describe = (
                AsyncMock(side_effect=behavior)
                if isinstance(behavior, Exception)
                else AsyncMock(return_value=behavior)
            )
            return _client_context(client)

        await self._set_companions(info_a, info_c, dead)
        with patch.object(management.Client, "build", side_effect=build):
            self.manager._prune_dead_companion = True
            pruned = await self.manager.list_targets(only=TargetType.DEVICE)
            local.list_targets.assert_awaited_once_with(only=TargetType.DEVICE)
            self.assertEqual([target.udid for target in pruned], ["b", "a", "c"])
            self.assertIs(pruned[0], local_b)
            self.assertIs(pruned[1], connected_a)
            self.assertIs(pruned[2], connected_c)
            self.assertEqual(await self._stored_companions(), [info_a, info_c])

            await self.manager._companion_set.add_companion(dead)
            local.list_targets.reset_mock()
            self.manager._prune_dead_companion = False
            retained = await self.manager.list_targets(only=TargetType.DEVICE)
            local.list_targets.assert_awaited_once_with(only=TargetType.DEVICE)
            self.assertEqual([target.udid for target in retained], ["b", "a", "c"])
            self.assertIs(retained[1], connected_a)
            self.assertIs(retained[2], connected_c)
            self.assertEqual(
                await self._stored_companions(),
                [info_a, info_c, dead],
            )

        self.assertEqual(
            _PENDING_MANAGEMENT_CORRECTIONS["compare_and_remove"], "pending"
        )
