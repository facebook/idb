#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from io import StringIO
from typing import AsyncIterator, Dict, List, Optional, Set

from idb.grpc.types import CompanionClient
from idb.common.constants import TESTS_POLL_INTERVAL
from idb.common.types import TestActivity, TestRunFailureInfo, TestRunInfo
from idb.grpc.idb_pb2 import XctestRunRequest, XctestRunResponse
from idb.common.tar import untar
from logging import Logger


Mode = XctestRunRequest.Mode
Logic = XctestRunRequest.Logic
Application = XctestRunRequest.Application
UI = XctestRunRequest.UI


def _make_request(
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
    )


async def _write_result_bundle(
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


def _make_results(response: XctestRunResponse) -> List[TestRunInfo]:
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
                TestActivity(
                    title=activity.title, duration=activity.duration, uuid=activity.uuid
                )
                for activity in result.activityLogs or []
            ],
            crashed=result.status == XctestRunResponse.TestRunInfo.CRASHED,
        )
        for result in response.results or []
    ]


async def run_xctest(
    client: CompanionClient,
    test_bundle_id: str,
    app_bundle_id: str,
    test_host_app_bundle_id: Optional[str] = None,
    is_ui_test: bool = False,
    is_logic_test: bool = False,
    tests_to_run: Optional[Set[str]] = None,
    tests_to_skip: Optional[Set[str]] = None,
    env: Optional[Dict[str, str]] = None,
    args: Optional[List[str]] = None,
    result_bundle_path: Optional[str] = None,
    idb_log_buffer: Optional[StringIO] = None,
    timeout: Optional[int] = None,
    poll_interval_sec: float = TESTS_POLL_INTERVAL,
) -> AsyncIterator[TestRunInfo]:
    async with client.stub.xctest_run.open() as stream:
        request = _make_request(
            test_bundle_id=test_bundle_id,
            app_bundle_id=app_bundle_id,
            test_host_app_bundle_id=test_host_app_bundle_id,
            is_ui_test=is_ui_test,
            is_logic_test=is_logic_test,
            tests_to_run=tests_to_run,
            tests_to_skip=tests_to_skip,
            env=env,
            args=args,
            result_bundle_path=result_bundle_path,
            timeout=timeout,
        )
        await stream.send_message(request, end=True)
        async for response in stream:
            for output in response.log_output:
                client.logger.info(output)
            if result_bundle_path:
                await _write_result_bundle(
                    response=response,
                    output_path=result_bundle_path,
                    logger=client.logger,
                )
            for result in _make_results(response):
                yield result


CLIENT_PROPERTIES = [run_xctest]  # pyre-ignore
