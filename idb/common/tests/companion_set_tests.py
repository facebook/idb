#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import tempfile
from pathlib import Path
from typing import AsyncGenerator
from unittest import mock

from idb.common.companion_set import CompanionSet
from idb.common.types import CompanionInfo, DomainSocketAddress, TCPAddress
from idb.utils.testing import ignoreTaskLeaks, TestCase


@ignoreTaskLeaks
class CompanionSetTests(TestCase):
    async def _managers(self) -> AsyncGenerator[CompanionSet, None]:
        # Covers a fresh tempfile
        with tempfile.NamedTemporaryFile() as f:
            yield CompanionSet(logger=mock.MagicMock(), state_file_path=f.name)
        # Covers a missing state file
        with tempfile.TemporaryDirectory() as dir:
            yield CompanionSet(
                logger=mock.MagicMock(), state_file_path=str(Path(dir) / "state_file")
            )
        # Covers a garbage tempfile
        with tempfile.TemporaryDirectory() as dir:
            path = str(Path(dir) / "state_file")
            with open(path, "w") as f:
                f.write("GARBAGEASDASDASD")
            yield CompanionSet(logger=mock.MagicMock(), state_file_path=path)

    async def test_add_multiple(self) -> None:
        async for manager in self._managers():
            companion_a = CompanionInfo(
                udid="a",
                address=TCPAddress(host="ahost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion_a)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a])
            companion_b = CompanionInfo(
                udid="b",
                address=TCPAddress(host="bhost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion_b)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_b])
            companion_c = CompanionInfo(
                udid="c",
                address=TCPAddress(host="chost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion_c)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_b, companion_c])
            removed = await manager.remove_companion(companion_b.address)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_c])
            self.assertEqual(removed, [companion_b])
            removed = await manager.remove_companion("a")
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_c])

    async def test_add_then_remove_companion_by_tcp_address(self) -> None:
        async for manager in self._managers():
            companion = CompanionInfo(
                udid="asdasda",
                address=TCPAddress(host="foohost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion])
            removed = await manager.remove_companion(companion.address)
            companions = await manager.get_companions()
            self.assertEqual(companions, [])
            self.assertEqual(removed, [companion])

    async def test_add_then_remove_companion_by_uxd_address(self) -> None:
        async for manager in self._managers():
            companion = CompanionInfo(
                udid="asdasda",
                address=DomainSocketAddress(path="/tmp/foo.sock"),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion])
            removed = await manager.remove_companion(companion.address)
            companions = await manager.get_companions()
            self.assertEqual(companions, [])
            self.assertEqual(removed, [companion])

    async def test_add_then_remove_companion_by_udid(self) -> None:
        async for manager in self._managers():
            companion = CompanionInfo(
                udid="asdasda",
                address=TCPAddress(host="foohost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion])
            removed = await manager.remove_companion("asdasda")
            companions = await manager.get_companions()
            self.assertEqual(companions, [])
            self.assertEqual(removed, [companion])

    async def test_add_then_clear(self) -> None:
        async for manager in self._managers():
            first = CompanionInfo(
                udid="asdasda",
                address=TCPAddress(host="foohost", port=123),
                is_local=False,
                pid=None,
            )
            second = CompanionInfo(
                udid="fooo",
                address=DomainSocketAddress(path="/bar/bar"),
                is_local=False,
                pid=324,
            )
            await manager.add_companion(first)
            await manager.add_companion(second)
            companions = await manager.get_companions()
            self.assertEqual(companions, [first, second])
            cleared = await manager.clear()
            companions = await manager.get_companions()
            self.assertEqual(companions, [])
            self.assertEqual(cleared, [first, second])

    async def test_replace_companion(self) -> None:
        async for manager in self._managers():
            companion_first = CompanionInfo(
                udid="a",
                address=TCPAddress(host="ahost", port=123),
                is_local=False,
                pid=None,
            )
            replaced = await manager.add_companion(companion_first)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_first])
            companion_second = CompanionInfo(
                udid="a",
                address=DomainSocketAddress(path="/some/path"),
                is_local=False,
                pid=123,
            )
            replaced = await manager.add_companion(companion_second)
            self.assertEqual(replaced, companion_first)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_second])
