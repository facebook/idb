#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from unittest import mock
from typing import TypeVar, AsyncContextManager, Optional, Type
from types import TracebackType

from idb.common.types import Address, CompanionInfo, TargetDescription
from idb.manager.companion import CompanionManager
from idb.utils.testing import TestCase, ignoreTaskLeaks


_T = TypeVar("_T")


class AsyncContextManagerDouble(AsyncContextManager[_T]):
    def __init__(self, value: _T) -> None:
        self.value = value

    async def __aenter__(self) -> _T:
        return self.value

    async def __aexit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        pass


TEST_COMPANION = CompanionInfo(
    udid="someUdid", host="myHost", port=1234, is_local=False, grpc_port=1235
)


def add_companion(
    companion_manager: CompanionManager, companion: CompanionInfo = TEST_COMPANION
) -> None:
    companion_manager.add_companion(companion)


@ignoreTaskLeaks
class CompanionManagerTest(TestCase):
    async def test_add_companion_with_host_and_port_adds_companion(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        companion_manager.add_companion(
            CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False, grpc_port=124
            )
        )
        assert companion_manager._udid_companion_map["asdasda"]

    async def test_add_companion_assigns_to_target(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        companion_manager.update_target(
            TargetDescription(
                udid="asdasda",
                name="iPhone",
                state="Booted",
                target_type="simulator",
                os_version="iOS 11.4",
                architecture="x86_64",
                companion_info=None,
                screen_dimensions=None,
            )
        )
        companion_manager.add_companion(
            CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False, grpc_port=124
            )
        )
        assert companion_manager._udid_target_map["asdasda"].companion_info

    async def test_closes_spawner_on_close(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        spawner = mock.Mock()
        companion_manager.companion_spawner = spawner
        companion_manager.channel = mock.Mock()
        companion_manager.close()
        spawner.close.assert_called_once()

    async def test_remove_companion_by_address(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        add_companion(companion_manager, TEST_COMPANION)
        self.assertEqual(len(companion_manager._udid_companion_map), 1)
        self.assertEqual(len(companion_manager._udid_target_map), 1)
        result = companion_manager.remove_companion(
            Address(
                host=TEST_COMPANION.host,
                port=TEST_COMPANION.port,
                grpc_port=TEST_COMPANION.grpc_port,
            )
        )
        self.assertEqual(result, TEST_COMPANION)
        self.assertEqual(len(companion_manager._udid_companion_map), 0)
        self.assertEqual(len(companion_manager._udid_target_map), 0)

    async def test_remove_companion_by_udid(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        add_companion(companion_manager, TEST_COMPANION)
        self.assertEqual(len(companion_manager._udid_companion_map), 1)
        self.assertEqual(len(companion_manager._udid_target_map), 1)
        result = companion_manager.remove_companion(TEST_COMPANION.udid)
        self.assertEqual(result, TEST_COMPANION)
        self.assertEqual(len(companion_manager._udid_companion_map), 0)
        self.assertEqual(len(companion_manager._udid_target_map), 0)

    async def test_get_default_companion(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        self.assertFalse(companion_manager.has_default_companion())
        add_companion(companion_manager, TEST_COMPANION)
        self.assertTrue(companion_manager.has_default_companion())
        self.assertEqual(companion_manager.get_default_companion(), TEST_COMPANION)
        companion_manager.add_companion(
            CompanionInfo(
                udid="someOtherUdid",
                host=TEST_COMPANION.host,
                port=TEST_COMPANION.port,
                is_local=TEST_COMPANION.is_local,
                grpc_port=TEST_COMPANION.grpc_port,
            )
        )
        self.assertFalse(companion_manager.has_default_companion())

    async def test_get_existing_companion(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        add_companion(companion_manager, TEST_COMPANION)
        async with companion_manager.create_companion_for_target_with_udid(
            TEST_COMPANION.udid, None
        ) as yielded_compainion:
            self.assertEqual(yielded_compainion, TEST_COMPANION)

    async def test_creates_default_companion(self) -> None:
        companion_manager = CompanionManager(
            companion_path=None, logger=mock.MagicMock()
        )
        add_companion(companion_manager, TEST_COMPANION)
        async with companion_manager.create_companion_for_target_with_udid(
            None, None
        ) as yielded_compainion:
            self.assertEqual(yielded_compainion, TEST_COMPANION)
