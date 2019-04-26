#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import os.path
import plistlib
import tempfile
from unittest import TestCase

from idb.common.xctest import extract_paths_from_xctestrun


class XCTestsTestCase(TestCase):
    async def test_extract_paths_from_xctestrun(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            file_path = os.path.join(tmp_dir, "test.plist")
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
