#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json

from idb.common.format import (
    installed_app_info_from_json,
    installed_test_info_from_json,
    json_data_companions,
    json_format_installed_app_info,
    json_format_installed_test_info,
    json_format_target_info,
    json_format_test_info,
    json_to_companion_info,
    target_description_from_json,
    test_info_from_json,
)
from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    InstalledAppInfo,
    InstalledTestInfo,
    TargetDescription,
    TestActivity,
    TestRunFailureInfo,
    TestRunInfo,
)
from idb.utils.testing import TestCase


TEST_RUN_FAILURE_INFO_FIXTURE = TestRunFailureInfo(
    message="FailedMsg", file="test.py", line=7
)
TEST_ACTIVITY_FIXTURE = TestActivity(title="ActivityTitle", duration=8, uuid="MyUdid")
TEST_RUN_INFO_FIXTURE = TestRunInfo(
    bundle_name="MyBundleName",
    class_name="MyClassName",
    method_name="MyMethodName",
    logs=["logA", "logB"],
    duration=12.34,
    passed=True,
    failure_info=None,
    activityLogs=[],
    crashed=False,
)
INSTALLED_APP_INFO_FIXTURE = InstalledAppInfo(
    bundle_id="MyBundleId",
    name="MyName",
    architectures={"ArchA", "ArchB"},
    install_type="System",
    process_state=AppProcessState.RUNNING,
    debuggable=True,
)
COMPANION_INFO_FIXTURE = CompanionInfo(
    udid="MyUdid", host="ThisMac", port=1234, is_local=False
)
TARGET_DESCRIPTION_FIXTURE = TargetDescription(
    udid="MyUdid",
    name="MyName",
    state="Started?",
    target_type="iOS",
    os_version="1",
    architecture="arm89",
    companion_info=None,
    screen_dimensions=None,
)
INSTALLED_TEST_INFO = InstalledTestInfo(
    bundle_id="MyBundleID", name="MyName", architectures={"ArchA", "ArchB"}
)


class FormattingTests(TestCase):
    def test_json_to_companion_info(self) -> None:
        self.assertEqual(
            [COMPANION_INFO_FIXTURE],
            json_to_companion_info(json_data_companions([COMPANION_INFO_FIXTURE])),
        )

    def test_test_info_no_optional_fields(self) -> None:
        self.assertEqual(
            TEST_RUN_INFO_FIXTURE,
            test_info_from_json(json_format_test_info(TEST_RUN_INFO_FIXTURE)),
        )

    def test_test_info_all_optional_fields(self) -> None:
        info = TEST_RUN_INFO_FIXTURE._replace(
            failure_info=TEST_RUN_FAILURE_INFO_FIXTURE,
            activityLogs=[TEST_ACTIVITY_FIXTURE],
        )
        self.assertEqual(info, test_info_from_json(json_format_test_info(info)))

    def test_installed_app_info(self) -> None:
        self.assertEqual(
            INSTALLED_APP_INFO_FIXTURE,
            installed_app_info_from_json(
                json_format_installed_app_info(INSTALLED_APP_INFO_FIXTURE)
            ),
        )

    def test_target_description_no_optional_fields(self) -> None:
        self.assertEqual(
            TARGET_DESCRIPTION_FIXTURE,
            target_description_from_json(
                json_format_target_info(TARGET_DESCRIPTION_FIXTURE)
            ),
        )

    def test_target_description_all_optional_fields(self) -> None:
        target = TARGET_DESCRIPTION_FIXTURE._replace(
            companion_info=COMPANION_INFO_FIXTURE
        )
        self.assertEqual(
            target, target_description_from_json(json_format_target_info(target))
        )

    def test_installed_test_info(self) -> None:
        self.assertEqual(
            INSTALLED_TEST_INFO,
            installed_test_info_from_json(
                json_format_installed_test_info(INSTALLED_TEST_INFO)
            ),
        )
