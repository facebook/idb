#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from unittest.mock import AsyncMock, MagicMock

from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.common.types import HIDHinge, IdbException
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import HingeAngleRequest, HingeAngleResponse
from idb.utils.testing import TestCase


class HingeTests(TestCase):
    def setUp(self) -> None:
        super().setUp()
        self.client = Client.__new__(Client)
        self.client.logger = MagicMock()
        self.client.stub = MagicMock()
        self.client.stub.hinge_angle = AsyncMock()

    async def test_get_reads_again_after_an_external_change(self) -> None:
        self.client.stub.hinge_angle.side_effect = [
            HingeAngleResponse(angle=0),
            HingeAngleResponse(angle=130),
            HingeAngleResponse(angle=180),
        ]
        for expected in [0, 130, 180]:
            self.assertEqual(await self.client.get_hinge_angle(), expected)
        self.assertEqual(self.client.stub.hinge_angle.await_count, 3)
        self.client.stub.hinge_angle.assert_awaited_with(HingeAngleRequest())

    async def test_get_failure_does_not_report_closed(self) -> None:
        self.client.stub.hinge_angle.side_effect = GRPCError(
            Status.UNAVAILABLE, "motion provider unavailable"
        )
        with self.assertRaises(IdbException):
            await self.client.get_hinge_angle()

    async def test_set_delegates_to_hid(self) -> None:
        self.client.send_events = AsyncMock()
        await self.client.set_hinge_angle(130)
        self.client.send_events.assert_awaited_once_with([HIDHinge(angle=130)])
