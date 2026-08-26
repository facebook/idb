#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from idb.common.format import (
    human_format_activities,
    json_data_companions,
    json_format_target_info,
    json_to_companion_info,
    target_description_from_json,
)
from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    InstalledAppInfo,
    InstalledTestInfo,
    TargetDescription,
    TargetType,
    TCPAddress,
    TestActivity,
    TestAttachment,
    TestRunFailureInfo,
    TestRunInfo,
)
from idb.utils.testing import TestCase


TEST_RUN_FAILURE_INFO_FIXTURE = TestRunFailureInfo(
    message="FailedMsg", file="test.py", line=7
)
TEST_ACTIVITY_FIXTURE = TestActivity(
    title="ActivityTitle",
    duration=8,
    uuid="MyUdid",
    activity_type="type",
    start=1,
    finish=2,
    name="name",
    attachments=[],
    sub_activities=[],
)
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
    process_id=0,
)
COMPANION_INFO_FIXTURE = CompanionInfo(
    udid="MyUdid",
    address=TCPAddress(host="ThisMac", port=1234),
    is_local=False,
    pid=123,
)
TARGET_DESCRIPTION_FIXTURE = TargetDescription(
    udid="MyUdid",
    name="MyName",
    state="Started?",
    target_type=TargetType.SIMULATOR,
    os_version="1",
    architecture="arm89",
    companion_info=None,
    screen_dimensions=None,
)
INSTALLED_TEST_INFO = InstalledTestInfo(
    bundle_id="MyBundleID", name="MyName", architectures={"ArchA", "ArchB"}
)
NESTED_ACTIVITY_FIXTURE = TestActivity(
    title="Launch app",
    duration=1.0,
    uuid="uuid-launch",
    activity_type="internal",
    start=10.0,
    finish=11.0,
    name="Launch app",
    attachments=[],
    sub_activities=[
        TestActivity(
            title="Wait for idle",
            duration=0.25,
            uuid="uuid-wait",
            activity_type="internal",
            start=10.25,
            finish=10.5,
            name="Wait for idle",
            attachments=[],
            sub_activities=[
                TestActivity(
                    title="Poll runloop",
                    duration=0.1,
                    uuid="uuid-poll",
                    activity_type="internal",
                    start=10.3,
                    finish=10.4,
                    name="Poll runloop",
                    attachments=[],
                    sub_activities=[],
                )
            ],
        )
    ],
)
# sub_activities deliberately listed out of start order: rendering must order
# siblings by start, and the attachment (which inherits start=12.0 from its
# parent activity) must render ahead of both later-starting sub-activities.
ATTACHMENT_ACTIVITY_FIXTURE = TestActivity(
    title="Tap button",
    duration=1.0,
    uuid="uuid-tap",
    activity_type="internal",
    start=12.0,
    finish=13.0,
    name="Tap button",
    attachments=[
        TestAttachment(
            payload=b"fake-png-bytes",
            timestamp=12.1,
            name="Screenshot 1",
            uniform_type_identifier="public.png",
            user_info_json=b"",
        )
    ],
    sub_activities=[
        TestActivity(
            title="Assert hittable",
            duration=0.25,
            uuid="uuid-assert",
            activity_type="internal",
            start=12.5,
            finish=12.75,
            name="Assert hittable",
            attachments=[],
            sub_activities=[],
        ),
        TestActivity(
            title="Find element",
            duration=0.25,
            uuid="uuid-find",
            activity_type="internal",
            start=12.25,
            finish=12.5,
            name="Find element",
            attachments=[],
            sub_activities=[],
        ),
    ],
)


class FormattingTests(TestCase):
    def test_json_to_companion_info(self) -> None:
        self.assertEqual(
            [COMPANION_INFO_FIXTURE],
            json_to_companion_info(json_data_companions([COMPANION_INFO_FIXTURE])),
        )

    def test_target_description_no_optional_fields(self) -> None:
        self.assertEqual(
            TARGET_DESCRIPTION_FIXTURE,
            target_description_from_json(
                json_format_target_info(TARGET_DESCRIPTION_FIXTURE)
            ),
        )

    def test_human_format_activities(self) -> None:
        self.assertEqual(
            human_format_activities(
                [NESTED_ACTIVITY_FIXTURE, ATTACHMENT_ACTIVITY_FIXTURE]
            ),
            "Activities\n"
            "├── Launch app (1.00s)\n"
            "│   └── Wait for idle (0.50s)\n"
            "│       └── Poll runloop (0.40s)\n"
            "└── Tap button (3.00s)\n"
            "    ├── Attachment: Screenshot 1\n"
            "    ├── Find element (2.50s)\n"
            "    └── Assert hittable (2.75s)\n",
        )
