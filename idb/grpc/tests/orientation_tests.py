#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from unittest.mock import AsyncMock, MagicMock

from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.common.types import DeviceOrientation, HIDOrientationType, IdbException
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import (
    GetOrientationRequest,
    GetOrientationResponse,
    SetOrientationRequest,
)
from idb.utils.testing import TestCase


class OrientationTests(TestCase):
    def setUp(self) -> None:
        super().setUp()
        self.client = Client.__new__(Client)
        self.client.logger = MagicMock()
        self.client.stub = MagicMock()
        self.client.stub.get_orientation = AsyncMock()
        self.client.stub.set_orientation = AsyncMock()

    async def test_each_get_reads_current_physical_state(self) -> None:
        for orientation in DeviceOrientation:
            self.client.stub.get_orientation.return_value = GetOrientationResponse(
                orientation=GetOrientationResponse.Orientation.Value(orientation.name)
            )
            self.assertEqual(await self.client.get_orientation(), orientation)
        self.assertEqual(
            self.client.stub.get_orientation.await_count, len(DeviceOrientation)
        )
        self.client.stub.get_orientation.assert_awaited_with(GetOrientationRequest())

    async def test_read_failures_and_future_values_do_not_default_to_portrait(
        self,
    ) -> None:
        self.client.stub.get_orientation.return_value = GetOrientationResponse(
            orientation=99
        )
        with self.assertRaises(IdbException):
            await self.client.get_orientation()
        self.client.stub.get_orientation.side_effect = GRPCError(
            Status.UNAVAILABLE, "motion unavailable"
        )
        with self.assertRaises(IdbException):
            await self.client.get_orientation()

    async def test_set_uses_physical_orientation_rpc(self) -> None:
        self.client.send_events = AsyncMock()
        for orientation in HIDOrientationType:
            await self.client.set_orientation(orientation)
            self.client.stub.set_orientation.assert_awaited_with(
                SetOrientationRequest(orientation=orientation.value)
            )
        self.client.send_events.assert_not_awaited()
