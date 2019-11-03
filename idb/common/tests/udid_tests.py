#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.udid import is_udid
from idb.utils.testing import TestCase


class UdidTests(TestCase):
    def test_simulator_udid(self) -> None:
        self.assertTrue(is_udid("0B3311FA-234C-4665-950F-37544F690B61"))

    def test_old_device_udid(self) -> None:
        self.assertTrue(is_udid("c7a0d0d95952f9a0903b15231b7641780d39e105"))

    def test_new_device_udid(self) -> None:
        self.assertTrue(is_udid("00008020-008D4548007B4F26"))

    def test_bad(self) -> None:
        self.assertFalse(is_udid("Not a udid"))
        self.assertFalse(is_udid("localhost:12345"))
        self.assertFalse(is_udid("192.168.1.254:12345"))
