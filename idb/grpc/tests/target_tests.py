#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import unittest
from unittest.mock import AsyncMock, MagicMock

from idb.common.types import (
    CompanionInfo,
    Compression,
    TargetDescription,
    TargetType,
    TCPAddress,
)
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import CompanionInfo as GrpcCompanionInfo, FocusRequest, Payload
from idb.grpc.target import companion_to_py, merge_connected_targets
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


class CompanionToPyTests(unittest.TestCase):
    def test_maps_supported_compressions(self) -> None:
        companion = companion_to_py(
            companion=GrpcCompanionInfo(
                udid="a", supported_compressions=[Payload.GZIP, Payload.ZSTD]
            ),
            address=TCPAddress(host="localhost", port=1),
        )
        self.assertEqual(
            companion.supported_compressions,
            frozenset({Compression.GZIP, Compression.ZSTD}),
        )

    def test_maps_zstd_zip_streams(self) -> None:
        address = TCPAddress(host="localhost", port=1)
        self.assertTrue(
            companion_to_py(
                companion=GrpcCompanionInfo(udid="a", zstd_zip_streams=True),
                address=address,
            ).zstd_zip_streams
        )
        self.assertFalse(
            companion_to_py(
                companion=GrpcCompanionInfo(udid="a"), address=address
            ).zstd_zip_streams
        )

    def test_omits_unknown_compressions(self) -> None:
        companion = companion_to_py(
            companion=GrpcCompanionInfo(udid="a", supported_compressions=[99]),
            address=TCPAddress(host="localhost", port=1),
        )
        self.assertEqual(companion.supported_compressions, frozenset())


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
