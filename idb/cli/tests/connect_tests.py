#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.connect import get_destination
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class TestParser(TestCase):
    async def test_get_destination_from_host_and_port(self):
        namespace = Namespace()
        host = "localhost"
        port = 1234
        namespace.companion = host
        namespace.port = port
        namespace.grpc_port = None
        address = get_destination(args=namespace)
        self.assertEqual(address.host, host)
        self.assertEqual(address.port, port)

    async def test_get_destination_from_host_and_port_and_grpc_port(self):
        namespace = Namespace()
        host = "localhost"
        port = 1234
        grpc_port = 1235
        namespace.companion = host
        namespace.port = port
        namespace.grpc_port = grpc_port
        address = get_destination(args=namespace)
        self.assertEqual(address.host, host)
        self.assertEqual(address.port, port)
        self.assertEqual(address.grpc_port, grpc_port)

    async def test_get_destination_from_target_udid(self):
        namespace = Namespace()
        target_udid = "SFASAF-ASFAFGE"
        namespace.companion = target_udid
        udid = get_destination(args=namespace)
        self.assertEqual(target_udid, udid)
