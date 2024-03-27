#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from idb.common.networking import _get_ports
from idb.utils.testing import ignoreTaskLeaks, TestCase


@ignoreTaskLeaks
class NetworkingTests(TestCase):
    def test_get_ports(self) -> None:
        data = '{"grpc_port": 1235}'
        ports = _get_ports(data)
        self.assertEqual(ports, (1235))
