#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import os
import plistlib
from enum import Enum
from typing import Any, Dict, List


class XCTestException(Exception):
    pass


class _XCTestType(Enum):
    XCTest = 0
    XCTestRun = 1


def _get_xctest_type(path: str) -> _XCTestType:
    if path.endswith(".xctestrun") and os.path.isfile(path):
        return _XCTestType.XCTestRun
    if path.endswith(".xctest") and os.path.isdir(path):
        return _XCTestType.XCTest
    raise XCTestException(f"{path} is not a valid xctest target")


def extract_paths_from_xctestrun(path: str) -> List[str]:
    """
    When using xctestrun we need to copy:
    - the xctestrun file
    - the host app directory that is specified in the xctestrun file for
    every test.
    This method returns paths to those.
    """
    result = [path]
    test_root = os.path.dirname(path)
    with open(path, "rb") as f:
        xctestrun_dict: Dict[str, Any] = plistlib.load(f, use_builtin_types=True)
        for _test_id, test_dict in xctestrun_dict.items():
            result.append(test_dict["TestHostPath"].replace("__TESTROOT__", test_root))
    return result


def xctest_paths_to_tar(bundle_path: str) -> List[str]:
    test_type = _get_xctest_type(bundle_path)
    if test_type is _XCTestType.XCTest:
        return [bundle_path]
    with open(bundle_path, "rb") as f:
        plist: Dict[str, Any] = plistlib.load(f)
        use_artifacts = (
            v.get("UseDestinationArtifacts", False) is True for v in plist.values()
        )

    if not all(use_artifacts):
        return extract_paths_from_xctestrun(bundle_path)
    else:
        return [bundle_path]
