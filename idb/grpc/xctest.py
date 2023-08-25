#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
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
    CodeCoverageFormat,
    TestActivity,
    TestAttachment,
    TestRunFailureInfo,
    TestRunInfo,
)
from idb.grpc.idb_pb2 import Payload, XctestRunRequest, XctestRunResponse
from idb.grpc.xctest_log_parser import XCTestLogParser


Mode = XctestRunRequest.Mode
Logic = XctestRunRequest.Logic
Application = XctestRunRequest.Application
UI = XctestRunRequest.UI

CODE_COVERAGE_FORMAT_MAP: Dict[
    CodeCoverageFormat, "XctestRunRequest.CodeCoverage.Format"
] = {
    CodeCoverageFormat.EXPORTED: XctestRunRequest.CodeCoverage.EXPORTED,
    CodeCoverageFormat.RAW: XctestRunRequest.CodeCoverage.RAW,
}


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


def extract_paths_from_xctestrun(
    path: str, logger: Optional[Logger] = None
) -> List[str]:
    """
    When using xctestrun we need to copy:
    - the xctestrun file
    - the host app directory that is specified in the xctestrun file for
    every test if the directory exists on the client host.
    This method returns paths to those.
    """
    result = [path]
    test_root = os.path.dirname(path)
    with open(path, "rb") as f:
        xctestrun_dict: Dict[str, Any] = plistlib.load(f)
        for _test_id, test_dict in xctestrun_dict.items():
            if _test_id == "__xctestrun_metadata__":
                continue
            testHostPath = test_dict["TestHostPath"].replace("__TESTROOT__", test_root)
            if os.path.exists(testHostPath):
                result.append(testHostPath)
            elif logger:
                logger.info(
                    f"{testHostPath} does not exist on the client host. "
                    + "It should be a valid path on the companion host."
                )
    return result


def xctest_paths_to_tar(bundle_path: str, logger: Optional[Logger] = None) -> List[str]:
    test_type = _get_xctest_type(bundle_path)
    if test_type is _XCTestType.XCTest:
        return [bundle_path]
    with open(bundle_path, "rb") as f:
        plist: Dict[str, Any] = plistlib.load(f)
        use_artifacts = (
            v.get("UseDestinationArtifacts", False) is True for v in plist.values()
        )

    if not all(use_artifacts):
        return extract_paths_from_xctestrun(bundle_path, logger)
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
    report_attachments: bool,
    collect_coverage: bool,
    enable_continuous_coverage_collection: bool,
    coverage_format: CodeCoverageFormat,
    collect_logs: bool,
    wait_for_debugger: bool,
    collect_result_bundle: bool,
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

    coverage_object = None
    if collect_coverage:

        coverage_object = XctestRunRequest.CodeCoverage(
            collect=True,
            enable_continuous_coverage_collection=enable_continuous_coverage_collection,
            format=CODE_COVERAGE_FORMAT_MAP[coverage_format],
        )

    return XctestRunRequest(
        arguments=args,
        collect_coverage=collect_coverage,
        environment=env,
        mode=mode,
        report_activities=report_activities,
        report_attachments=report_attachments,
        test_bundle_id=test_bundle_id,
        tests_to_run=list(tests_to_run or []),
        tests_to_skip=list(tests_to_skip or []),
        timeout=(timeout if timeout is not None else 0),
        collect_logs=collect_logs,
        wait_for_debugger=wait_for_debugger,
        code_coverage=coverage_object,
        collect_result_bundle=collect_result_bundle,
    )


async def untar_into_path(
    payload: Payload, description: str, output_path: str, logger: Logger
) -> None:
    if not payload:
        return
    data = payload.data
    if not len(data):
        return
    logger.info(f"Writing {description} to {output_path}")
    await untar(data=data, output_path=output_path)
    logger.info(f"Finished writing {description} to {output_path}")


def make_results(
    response: XctestRunResponse, log_parser: XCTestLogParser
) -> List[TestRunInfo]:
    return [
        TestRunInfo(
            bundle_name=result.bundle_name,
            class_name=result.class_name,
            method_name=result.method_name,
            logs=(
                list(result.logs)
                + log_parser.get_logs_for_test(result.class_name, result.method_name)
            ),
            duration=result.duration,
            passed=result.status == XctestRunResponse.TestRunInfo.PASSED,
            failure_info=(make_failure_info(result) if result.failure_info else None),
            activityLogs=[
                translate_activity(activity) for activity in result.activityLogs or []
            ],
            crashed=result.status == XctestRunResponse.TestRunInfo.CRASHED,
        )
        for result in response.results or []
    ]


def make_failure_info(result: XctestRunResponse.TestRunInfo) -> TestRunFailureInfo:
    if result.other_failures is None or len(result.other_failures) == 0:
        return TestRunFailureInfo(
            message=result.failure_info.failure_message,
            file=result.failure_info.file,
            line=result.failure_info.line,
        )
    else:
        message = (
            "line:"
            + str(result.failure_info.line)
            + " "
            + result.failure_info.failure_message
        )
        for other_failure in result.other_failures:
            message = (
                message
                + ", line:"
                + str(other_failure.line)
                + " "
                + other_failure.failure_message
            )
        return TestRunFailureInfo(
            message=message,
            file=result.failure_info.file,
            line=result.failure_info.line,
        )


def translate_activity(
    activity: XctestRunResponse.TestRunInfo.TestActivity,
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
                user_info_json=attachment.user_info_json,
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
