#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.networking import _get_ports
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class NetworkingTests(TestCase):
    def test_get_ports(self) -> None:
        data = '{"grpc_port": 1235}'
        ports = _get_ports(data)
        self.assertEqual(ports, (1235))
