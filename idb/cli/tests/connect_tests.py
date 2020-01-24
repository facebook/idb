#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import Namespace

from idb.cli.commands.target import get_destination
from idb.common.types import Address
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class TestParser(TestCase):
    async def test_get_destination_from_host_and_port(self) -> None:
        namespace = Namespace()
        host = "localhost"
        port = 1234
        namespace.companion = host
        namespace.port = port
        address = get_destination(args=namespace)
        assert isinstance(address, Address)
        self.assertEqual(address.host, host)
        self.assertEqual(address.port, port)

    async def test_get_destination_from_target_udid(self) -> None:
        namespace = Namespace()
        target_udid = "0B3311FA-234C-4665-950F-37544F690B61"
        namespace.companion = target_udid
        udid = get_destination(args=namespace)
        self.assertEqual(target_udid, udid)
