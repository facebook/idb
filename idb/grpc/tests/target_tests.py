#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import unittest
from unittest.mock import AsyncMock, MagicMock

from idb.common.types import CompanionInfo, TargetDescription, TargetType, TCPAddress
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import FocusRequest
from idb.grpc.target import merge_connected_targets
from idb.utils.testing import TestCase


class TargetTests(unittest.TestCase):
    def test_merge_connected_targets(self) -> None:
        merged_targets = merge_connected_targets(
            local_targets=[
                TargetDescription(
                    udid="a",
                    name="aa",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="b",
                    name="bb",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="c",
                    name="cc",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
            ],
            connected_targets=[
                TargetDescription(
                    udid="a",
                    name="aa",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="a",
                        address=TCPAddress(host="remotehost", port=1),
                        is_local=False,
                        pid=None,
                    ),
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="d",
                    name="dd",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="d",
                        address=TCPAddress(host="remotehost", port=2),
                        is_local=False,
                        pid=None,
                    ),
                    screen_dimensions=None,
                ),
            ],
        )
        self.assertEqual(
            merged_targets,
            [
                TargetDescription(
                    udid="a",
                    name="aa",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="a",
                        address=TCPAddress(host="remotehost", port=1),
                        is_local=False,
                        pid=None,
                    ),
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="b",
                    name="bb",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="c",
                    name="cc",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="d",
                    name="dd",
                    state=None,
                    target_type=TargetType.SIMULATOR,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="d",
                        address=TCPAddress(host="remotehost", port=2),
                        is_local=False,
                        pid=None,
                    ),
                    screen_dimensions=None,
                ),
            ],
        )


class FocusTests(TestCase):
    def setUp(self) -> None:
        super().setUp()
        self.client = Client.__new__(Client)
        self.client.logger = MagicMock()
        self.client.stub = MagicMock()
        self.client.stub.focus = AsyncMock()

    async def test_focus_sends_one_unary_request(self) -> None:
        await self.client.focus()

        self.client.stub.focus.assert_awaited_once_with(FocusRequest())
