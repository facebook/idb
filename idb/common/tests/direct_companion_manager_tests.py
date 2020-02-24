#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import tempfile
from pathlib import Path
from typing import AsyncGenerator
from unittest import mock

from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.types import Address, CompanionInfo, IdbException
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionManagerTests(TestCase):
    async def _managers(self) -> AsyncGenerator[DirectCompanionManager, None]:
        with tempfile.NamedTemporaryFile() as f:
            yield DirectCompanionManager(
                logger=mock.MagicMock(), state_file_path=f.name
            )
        with tempfile.TemporaryDirectory() as dir:
            yield DirectCompanionManager(
                logger=mock.MagicMock(), state_file_path=str(Path(dir) / "state_file")
            )

    async def test_add_multiple(self) -> None:
        async for manager in self._managers():
            companion_a = CompanionInfo(
                udid="a", host="ahost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_a)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a])
            companion_b = CompanionInfo(
                udid="b", host="bhost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_b)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_b])
            companion_c = CompanionInfo(
                udid="c", host="chost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_c)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_b, companion_c])
            removed = await manager.remove_companion(
                Address(host=companion_b.host, port=companion_b.port)
            )
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_c])
            self.assertEqual(removed, [companion_b])
            removed = await manager.remove_companion("a")
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_c])

    async def test_add_then_remove_companion_by_address(self) -> None:
        async for manager in self._managers():
            companion = CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion])
            removed = await manager.remove_companion(
                Address(host=companion.host, port=companion.port)
            )
            companions = await manager.get_companions()
            self.assertEqual(companions, [])
            self.assertEqual(removed, [companion])

    async def test_add_then_remove_companion_by_udid(self) -> None:
        async for manager in self._managers():
            companion = CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False
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
            companion = CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False
            )
            await manager.add_companion(companion)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion])
            await manager.clear()
            companions = await manager.get_companions()
            self.assertEqual(companions, [])

    async def test_ambiguous_companions(self) -> None:
        async for manager in self._managers():
            companion_a = CompanionInfo(
                udid="a", host="ahost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_a)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a])
            companion_b = CompanionInfo(
                udid="b", host="ahost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_b)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_a, companion_b])
            with self.assertRaises(IdbException):
                await manager.get_companion_info(target_udid=None)

    async def test_replace_companion(self) -> None:
        async for manager in self._managers():
            companion_first = CompanionInfo(
                udid="a", host="ahost", port=123, is_local=False
            )
            replaced = await manager.add_companion(companion_first)
            self.assertIsNone(replaced)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_first])
            companion_second = CompanionInfo(
                udid="a", host="anotherhost", port=321, is_local=False
            )
            replaced = await manager.add_companion(companion_second)
            self.assertEqual(replaced, companion_first)
            companions = await manager.get_companions()
            self.assertEqual(companions, [companion_second])
