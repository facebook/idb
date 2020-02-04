#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.tar import _create_untar_command
from idb.utils.testing import TestCase


class UdidTests(TestCase):
    def test_untar_command(self) -> None:
        output_path = "test_output_path"
        self.assertEqual(
            _create_untar_command(output_path=output_path, verbose=False),
            f"tar -C '{output_path}' --warning=no-unknown-keyword -xzpf -",
        )
        self.assertEqual(
            _create_untar_command(output_path=output_path, verbose=True),
            f"tar -C '{output_path}'  -xzpfv -",
        )
