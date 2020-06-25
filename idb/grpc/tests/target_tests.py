#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from unittest import TestCase

from idb.common.types import CompanionInfo, TargetDescription, TCPAddress
from idb.grpc.target import merge_connected_targets


class TargetTests(TestCase):
    def test_merge_connected_targets(self) -> None:
        merged_targets = merge_connected_targets(
            local_targets=[
                TargetDescription(
                    udid="a",
                    name="aa",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="b",
                    name="bb",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="c",
                    name="cc",
                    state=None,
                    target_type=None,
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
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="a",
                        address=TCPAddress(host="remotehost", port=1),
                        is_local=False,
                    ),
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="d",
                    name="dd",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="d",
                        address=TCPAddress(host="remotehost", port=2),
                        is_local=False,
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
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="a",
                        address=TCPAddress(host="remotehost", port=1),
                        is_local=False,
                    ),
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="b",
                    name="bb",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="c",
                    name="cc",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=None,
                    screen_dimensions=None,
                ),
                TargetDescription(
                    udid="d",
                    name="dd",
                    state=None,
                    target_type=None,
                    os_version=None,
                    architecture=None,
                    companion_info=CompanionInfo(
                        udid="d",
                        address=TCPAddress(host="remotehost", port=2),
                        is_local=False,
                    ),
                    screen_dimensions=None,
                ),
            ],
        )
