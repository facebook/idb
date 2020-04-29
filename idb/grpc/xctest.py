#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
import plistlib
from enum import Enum
from logging import Logger
from typing import Any, Dict, List, Optional, Set

from idb.common.tar import untar
from idb.common.types import (
    TestActivity,
    TestAttachment,
    TestRunFailureInfo,
    TestRunInfo,
)
from idb.grpc.idb_pb2 import XctestRunRequest, XctestRunResponse


Mode = XctestRunRequest.Mode
Logic = XctestRunRequest.Logic
Application = XctestRunRequest.Application
UI = XctestRunRequest.UI


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


def make_request(
    test_bundle_id: str,
    app_bundle_id: str,
    test_host_app_bundle_id: Optional[str],
    is_ui_test: bool,
    is_logic_test: bool,
    tests_to_run: Optional[Set[str]],
    tests_to_skip: Optional[Set[str]],
    env: Optional[Dict[str, str]],
    args: Optional[List[str]],
    result_bundle_path: Optional[str],
    timeout: Optional[int],
    report_activities: bool,
    collect_coverage: bool,
) -> XctestRunRequest:
    if is_logic_test:
        mode = Mode(logic=Logic())
    elif is_ui_test:
        mode = Mode(
            ui=UI(
                app_bundle_id=app_bundle_id,
                test_host_app_bundle_id=test_host_app_bundle_id,
            )
        )
    else:
        mode = Mode(application=Application(app_bundle_id=app_bundle_id))

    return XctestRunRequest(
        mode=mode,
        test_bundle_id=test_bundle_id,
        tests_to_run=list(tests_to_run or []),
        tests_to_skip=list(tests_to_skip or []),
        environment=env,
        arguments=args,
        report_activities=report_activities,
        collect_coverage=collect_coverage,
    )


async def write_result_bundle(
    response: XctestRunResponse, output_path: str, logger: Logger
) -> None:
    payload = response.result_bundle
    if not payload:
        return
    data = payload.data
    if not len(data):
        return
    logger.info(f"Writing result bundle to {output_path}")
    await untar(data=data, output_path=output_path)
    logger.info(f"Finished writing result bundle to {output_path}")


def make_results(response: XctestRunResponse) -> List[TestRunInfo]:
    return [
        TestRunInfo(
            bundle_name=result.bundle_name,
            class_name=result.class_name,
            method_name=result.method_name,
            logs=list(result.logs),
            duration=result.duration,
            passed=result.status == XctestRunResponse.TestRunInfo.PASSED,
            failure_info=(
                TestRunFailureInfo(
                    message=result.failure_info.failure_message,
                    file=result.failure_info.file,
                    line=result.failure_info.line,
                )
                if result.failure_info
                else None
            ),
            activityLogs=[
                translate_activity(activity) for activity in result.activityLogs or []
            ],
            crashed=result.status == XctestRunResponse.TestRunInfo.CRASHED,
        )
        for result in response.results or []
    ]


def translate_activity(
    activity: XctestRunResponse.TestRunInfo.TestActivity
) -> TestActivity:
    return TestActivity(
        title=activity.title,
        duration=activity.duration,
        uuid=activity.uuid,
        activity_type=activity.activity_type,
        start=activity.start,
        finish=activity.finish,
        name=activity.name,
        attachments=[
            TestAttachment(
                payload=attachment.payload,
                timestamp=attachment.timestamp,
                name=attachment.name,
                uniform_type_identifier=attachment.uniform_type_identifier,
            )
            for attachment in activity.attachments or []
        ],
        sub_activities=[
            translate_activity(sub_activity)
            for sub_activity in activity.sub_activities or []
        ],
    )


def save_attachments(run_info: TestRunInfo, activities_output_path: str) -> None:
    test_name = (
        f"{run_info.bundle_name} - {run_info.class_name} - {run_info.method_name}"
    )
    base_path = os.path.join(activities_output_path, test_name)
    os.makedirs(base_path)
    for activity in run_info.activityLogs or []:
        save_activities_attachments(activity, base_path)


def save_activities_attachments(activity: TestActivity, path: str) -> None:
    for attachment in activity.attachments:
        extension = attachment_to_file_extension(attachment)
        attachment_path = os.path.join(
            path,
            f"{attachment.timestamp} - {activity.name} - {attachment.name}.{extension}",
        )
        with open(attachment_path, "wb") as f:
            f.write(attachment.payload)
    for sub_activity in activity.sub_activities:
        save_activities_attachments(sub_activity, path)


def attachment_to_file_extension(attachment: TestAttachment) -> str:
    uti = attachment.uniform_type_identifier
    if uti == "public.jpeg":
        return "jpeg"
    elif uti == "public.png":
        return "png"
    else:
        return "data"
