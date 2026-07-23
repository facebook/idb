#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import asyncio
import logging
from collections.abc import Callable
from typing import Union
from unittest.mock import AsyncMock, MagicMock, patch

from idb.common.types import (
    CompanionInfo,
    DomainSocketAddress,
    IdbException,
    TargetDescription,
    TargetType,
)
from idb.grpc import management
from idb.grpc.management import _realize_companions
from idb.utils.testing import TestCase


# A per-address describe behavior is one of:
#   - TargetDescription: returned from `client.describe()`
#   - Exception: raised from `client.describe()`
#   - async callable: invoked as `await client.describe()` (for slow/timeout cases)
DescribeBehavior = Union[TargetDescription, Exception, Callable]


def _companion(udid: str) -> CompanionInfo:
    return CompanionInfo(
        address=DomainSocketAddress(path=f"/tmp/{udid}.sock"),
        udid=udid,
        is_local=True,
        pid=None,
    )


def _target(udid: str) -> TargetDescription:
    return TargetDescription(
        udid=udid,
        name=udid,
        state=None,
        target_type=TargetType.SIMULATOR,
        os_version=None,
        architecture=None,
        companion_info=None,
        screen_dimensions=None,
    )


async def _never_returns(*_args, **_kwargs) -> TargetDescription:
    """Hangs longer than any reasonable test timeout — used to trigger the
    `asyncio.wait_for` timeout in `_realize_companions`."""
    await asyncio.sleep(60)
    raise AssertionError("should have been cancelled by wait_for timeout")


def _build_fake_client_factory(
    behavior_for_address: Callable[[DomainSocketAddress], DescribeBehavior],
):
    """Returns a stand-in for `Client.build(...)`.

    The returned callable produces an async context manager whose `__aenter__`
    yields a client whose `describe()` is dispatched to the per-address behavior:
    a value (returned), an exception (raised), or a coroutine function (awaited).
    """

    def fake_build(*, address, logger):
        behavior = behavior_for_address(address)
        client = MagicMock()
        if isinstance(behavior, Exception) or (
            isinstance(behavior, type) and issubclass(behavior, BaseException)
        ):
            client.describe = AsyncMock(side_effect=behavior)
        elif callable(behavior):
            client.describe = AsyncMock(side_effect=behavior)
        else:
            client.describe = AsyncMock(return_value=behavior)
        cm = MagicMock()
        cm.__aenter__ = AsyncMock(return_value=client)
        cm.__aexit__ = AsyncMock(return_value=None)
        return cm

    return fake_build


class RealizeCompanionsTests(TestCase):
    def setUp(self) -> None:
        super().setUp()
        self.logger = logging.getLogger("idb_test")
        # Shrink timeout so "slow" companions trigger it without slowing tests.
        self._timeout_patch = patch.object(
            management, "COMPANION_CONNECT_TIMEOUT", 0.05
        )
        self._timeout_patch.start()
        self.addCleanup(self._timeout_patch.stop)

    def _patch_client_build(
        self, behavior_for_address: Callable[[DomainSocketAddress], DescribeBehavior]
    ) -> None:
        p = patch.object(management, "Client")
        client_cls = p.start()
        self.addCleanup(p.stop)
        client_cls.build = _build_fake_client_factory(behavior_for_address)

    def _make_companion_set(self, companions) -> MagicMock:
        cs = MagicMock()
        cs.get_companions = AsyncMock(return_value=list(companions))
        cs.remove_companion = AsyncMock()
        return cs

    async def test_returns_targets_when_all_companions_describe_successfully(
        self,
    ) -> None:
        a, b = _companion("a"), _companion("b")
        results = {a.address: _target("a"), b.address: _target("b")}
        self._patch_client_build(lambda addr: results[addr])
        cs = self._make_companion_set([a, b])

        result = await _realize_companions(
            companion_set=cs, prune_dead_companion=True, logger=self.logger
        )

        self.assertEqual({t.udid for t in result}, {"a", "b"})
        cs.remove_companion.assert_not_awaited()

    async def test_timeout_with_prune_removes_companion_and_omits_target(
        self,
    ) -> None:
        slow = _companion("slow")
        self._patch_client_build(lambda _addr: _never_returns)
        cs = self._make_companion_set([slow])

        result = await _realize_companions(
            companion_set=cs, prune_dead_companion=True, logger=self.logger
        )

        self.assertEqual(result, [])
        cs.remove_companion.assert_awaited_once_with(slow.address)

    async def test_timeout_without_prune_keeps_companion(self) -> None:
        slow = _companion("slow")
        self._patch_client_build(lambda _addr: _never_returns)
        cs = self._make_companion_set([slow])

        result = await _realize_companions(
            companion_set=cs, prune_dead_companion=False, logger=self.logger
        )

        self.assertEqual(result, [])
        cs.remove_companion.assert_not_awaited()

    async def test_describe_exception_with_prune_removes_companion(self) -> None:
        broken = _companion("broken")
        self._patch_client_build(lambda _addr: IdbException("boom"))
        cs = self._make_companion_set([broken])

        result = await _realize_companions(
            companion_set=cs, prune_dead_companion=True, logger=self.logger
        )

        self.assertEqual(result, [])
        cs.remove_companion.assert_awaited_once_with(broken.address)

    async def test_partial_success_returns_only_described_targets(self) -> None:
        good, slow = _companion("good"), _companion("slow")

        def behavior(address):
            if address == good.address:
                return _target("good")
            return _never_returns

        self._patch_client_build(behavior)
        cs = self._make_companion_set([good, slow])

        result = await _realize_companions(
            companion_set=cs, prune_dead_companion=True, logger=self.logger
        )

        self.assertEqual([t.udid for t in result], ["good"])
        cs.remove_companion.assert_awaited_once_with(slow.address)
