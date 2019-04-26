#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.networking import _get_ports
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class NetworkingTests(TestCase):
    def test_get_ports(self) -> None:
        data = '{"port": 1234, "grpc_port": 1235}'
        ports = _get_ports(data)
        self.assertEqual(ports, (1234, 1235))
