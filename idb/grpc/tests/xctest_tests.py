#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import os.path
import plistlib
import tempfile
from unittest import IsolatedAsyncioTestCase

from idb.grpc.xctest import extract_paths_from_xctestrun


class XCTestsTestCase(IsolatedAsyncioTestCase):
    async def test_extract_paths_from_xctestrun(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            file_path = os.path.join(tmp_dir, "test.plist")
            with open(os.path.join(tmp_dir, "rest1"), "w") as rest1:
                rest1.write("rest1")
            with open(os.path.join(tmp_dir, "rest2"), "w") as rest2:
                rest2.write("rest2")
            with open(file_path, "wb+") as f:
                plistlib.dump(
                    {
                        "key1": {"TestHostPath": "__TESTROOT__/rest1"},
                        "key2": {"TestHostPath": "__TESTROOT__/rest2"},
                    },
                    f,
                )
            results = extract_paths_from_xctestrun(file_path)
            self.assertEqual(
                [file_path, tmp_dir + "/rest1", tmp_dir + "/rest2"], results
            )
