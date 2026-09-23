#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import json
import os.path
import plistlib
import tempfile
from io import BytesIO, StringIO
from types import SimpleNamespace
from unittest import IsolatedAsyncioTestCase
from unittest.mock import AsyncMock, MagicMock, patch

from idb.common.types import CodeCoverageFormat
from idb.grpc.client import Client
from idb.grpc.idb_pb2 import (
    DebuggerInfo,
    Payload,
    XctestListBundlesRequest,
    XctestListBundlesResponse,
    XctestListTestsRequest,
    XctestListTestsResponse,
    XctestRunRequest,
    XctestRunResponse,
)
from idb.grpc.tests.stream_test_support import make_client, ScriptedStream
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

    async def test_list_bundles_request_and_response(self) -> None:
        cases = [
            (
                "ordered",
                XctestListBundlesResponse(
                    bundles=[
                        XctestListBundlesResponse.Bundles(
                            name="SecondTests",
                            bundle_id="com.example.SecondTests",
                            architectures=["arm64", "x86_64"],
                        ),
                        XctestListBundlesResponse.Bundles(
                            name="FirstTests",
                            bundle_id="com.example.FirstTests",
                            architectures=[],
                        ),
                    ]
                ),
                [
                    (
                        "com.example.SecondTests",
                        "SecondTests",
                        ["arm64", "x86_64"],
                    ),
                    ("com.example.FirstTests", "FirstTests", []),
                ],
            ),
            ("empty", XctestListBundlesResponse(), []),
        ]
        for name, response, expected in cases:
            with self.subTest(name=name):
                client = Client.__new__(Client)
                client.stub = MagicMock()
                client.logger = MagicMock()
                client.stub.xctest_list_bundles = AsyncMock(return_value=response)

                actual = await client.list_xctests()

                self.assertEqual(
                    [
                        (item.bundle_id, item.name, list(item.architectures or []))
                        for item in actual
                    ],
                    expected,
                )
                client.stub.xctest_list_bundles.assert_awaited_once_with(
                    XctestListBundlesRequest()
                )

    async def test_list_tests_request_and_response(self) -> None:
        cases = [
            (
                "ordered",
                XctestListTestsResponse(
                    names=[
                        "ExampleTests/testSecond",
                        "ExampleTests/testFirst",
                    ]
                ),
                ["ExampleTests/testSecond", "ExampleTests/testFirst"],
            ),
            ("empty", XctestListTestsResponse(), []),
        ]
        for name, response, expected in cases:
            with self.subTest(name=name):
                client = Client.__new__(Client)
                client.stub = MagicMock()
                client.logger = MagicMock()
                client.stub.xctest_list_tests = AsyncMock(return_value=response)

                actual = await client.list_test_bundle(
                    test_bundle_id="com.example.ExampleTests",
                    app_path="/Applications/Example.app",
                )

                self.assertEqual(actual, expected)
                client.stub.xctest_list_tests.assert_awaited_once_with(
                    XctestListTestsRequest(
                        bundle_name="com.example.ExampleTests",
                        app_path="/Applications/Example.app",
                    )
                )

    async def test_run_request_stream_results_artifacts_and_terminal_state(
        self,
    ) -> None:
        begin_pass = json.dumps(
            {
                "className": "ExampleTests",
                "methodName": "testPass",
                "event": "begin-test",
            }
        )
        end_pass = json.dumps(
            {
                "className": "ExampleTests",
                "methodName": "testPass",
                "event": "end-test",
            }
        )
        begin_crash = json.dumps(
            {
                "className": "ExampleTests",
                "methodName": "testCrash",
                "event": "begin-test",
            }
        )
        end_crash = json.dumps(
            {
                "className": "ExampleTests",
                "methodName": "testCrash",
                "event": "end-test",
            }
        )
        attachment = XctestRunResponse.TestRunInfo.TestAttachment(
            payload=b"png",
            timestamp=10.25,
            name="shot",
            uniform_type_identifier="public.png",
            user_info_json=b'{"scale":2}',
        )
        activity = XctestRunResponse.TestRunInfo.TestActivity(
            title="Tap",
            duration=0.5,
            uuid="activity-uuid",
            activity_type="userCreated",
            start=10.0,
            finish=10.5,
            name="Tap",
            attachments=[attachment],
        )
        running = XctestRunResponse(
            status=XctestRunResponse.RUNNING,
            results=[
                XctestRunResponse.TestRunInfo(
                    status=XctestRunResponse.TestRunInfo.PASSED,
                    bundle_name="ExampleTests",
                    class_name="ExampleTests",
                    method_name="testPass",
                    duration=1.25,
                    logs=["result-pass"],
                    activityLogs=[activity],
                )
            ],
            log_output=[begin_pass + "\n", "stream-pass\n", end_pass + "\n"],
            result_bundle=Payload(data=b"running-result"),
            log_directory=Payload(data=b"running-logs"),
            debugger=DebuggerInfo(pid=4242),
            code_coverage_data=Payload(data=b"running-coverage"),
        )
        terminal = XctestRunResponse(
            status=XctestRunResponse.TERMINATED_ABNORMALLY,
            results=[
                XctestRunResponse.TestRunInfo(
                    status=XctestRunResponse.TestRunInfo.CRASHED,
                    bundle_name="ExampleTests",
                    class_name="ExampleTests",
                    method_name="testCrash",
                    duration=0.5,
                    logs=["result-crash"],
                    failure_info=XctestRunResponse.TestRunInfo.TestRunFailureInfo(
                        failure_message="primary",
                        file="ExampleTests.swift",
                        line=7,
                    ),
                    other_failures=[
                        XctestRunResponse.TestRunInfo.TestRunFailureInfo(
                            failure_message="secondary",
                            file="ExampleTests.swift",
                            line=9,
                        )
                    ],
                )
            ],
            log_output=[
                begin_crash + "\n",
                "stream-crash\n",
                end_crash + "\n",
            ],
            result_bundle=Payload(data=b"terminal-result"),
            log_directory=Payload(data=b"terminal-logs"),
            code_coverage_data=Payload(data=b"terminal-coverage"),
        )
        stream = ScriptedStream[XctestRunResponse](running, terminal)
        client, open_rpc = make_client("xctest_run", stream)
        expected_request = XctestRunRequest(
            mode=XctestRunRequest.Mode(
                ui=XctestRunRequest.UI(
                    app_bundle_id="com.example.App",
                    test_host_app_bundle_id="com.example.TestHost",
                )
            ),
            test_bundle_id="com.example.ExampleTests",
            tests_to_run=["ExampleTests/testPass"],
            tests_to_skip=["ExampleTests/testSkip"],
            arguments=["--flag", "argument"],
            environment={"TEST_ENV": "value"},
            timeout=42,
            report_activities=True,
            collect_coverage=True,
            report_attachments=True,
            collect_logs=True,
            wait_for_debugger=True,
            code_coverage=XctestRunRequest.CodeCoverage(
                collect=True,
                format=XctestRunRequest.CodeCoverage.RAW,
                enable_continuous_coverage_collection=True,
            ),
            collect_result_bundle=True,
        )
        debugger_output = BytesIO()
        idb_log_buffer = StringIO()

        with (
            patch("idb.grpc.client.untar_into_path", new_callable=AsyncMock) as untar,
            patch(
                "idb.grpc.client.sys.stdout",
                SimpleNamespace(buffer=debugger_output),
            ),
        ):
            results = client.run_xctest(
                test_bundle_id="com.example.ExampleTests",
                app_bundle_id="com.example.App",
                test_host_app_bundle_id="com.example.TestHost",
                is_ui_test=True,
                tests_to_run={"ExampleTests/testPass"},
                tests_to_skip={"ExampleTests/testSkip"},
                env={"TEST_ENV": "value"},
                args=["--flag", "argument"],
                result_bundle_path="/tmp/result-bundle",
                timeout=42,
                report_activities=True,
                report_attachments=True,
                coverage_output_path="/tmp/coverage",
                enable_continuous_coverage_collection=True,
                coverage_format=CodeCoverageFormat.RAW,
                log_directory_path="/tmp/logs",
                wait_for_debugger=True,
                idb_log_buffer=idb_log_buffer,
            )

            passed = await anext(results)
            self.assertEqual(passed.method_name, "testPass")
            self.assertEqual(passed.logs, ["result-pass", "stream-pass"])
            self.assertTrue(passed.passed)
            self.assertFalse(passed.crashed)
            self.assertEqual(passed.activityLogs[0].attachments[0].payload, b"png")
            self.assertEqual(
                [call.kwargs["description"] for call in untar.await_args_list],
                ["result bundle", "log directory", "raw code coverage directory"],
            )
            self.assertEqual(debugger_output.getvalue(), b'{"pid": 4242}\n')

            crashed = await anext(results)
            self.assertEqual(crashed.method_name, "testCrash")
            self.assertEqual(crashed.logs, ["result-crash", "stream-crash"])
            self.assertFalse(crashed.passed)
            self.assertTrue(crashed.crashed)
            self.assertEqual(
                crashed.failure_info.message,
                "line:7 primary, line:9 secondary",
            )
            self.assertEqual(
                [call.kwargs["description"] for call in untar.await_args_list],
                [
                    "result bundle",
                    "log directory",
                    "raw code coverage directory",
                    "result bundle",
                    "log directory",
                    "raw code coverage directory",
                ],
            )
            with self.assertRaises(StopAsyncIteration):
                await anext(results)

        self.assertEqual(
            [
                (
                    call.kwargs["payload"],
                    call.kwargs["description"],
                    call.kwargs["output_path"],
                )
                for call in untar.await_args_list
            ],
            [
                (running.result_bundle, "result bundle", "/tmp/result-bundle"),
                (running.log_directory, "log directory", "/tmp/logs"),
                (
                    running.code_coverage_data,
                    "raw code coverage directory",
                    "/tmp/coverage",
                ),
                (terminal.result_bundle, "result bundle", "/tmp/result-bundle"),
                (terminal.log_directory, "log directory", "/tmp/logs"),
                (
                    terminal.code_coverage_data,
                    "raw code coverage directory",
                    "/tmp/coverage",
                ),
            ],
        )
        self.assertEqual(
            idb_log_buffer.getvalue(),
            begin_pass
            + "\nstream-pass\n"
            + end_pass
            + "\n"
            + begin_crash
            + "\nstream-crash\n"
            + end_crash
            + "\n",
        )
        self.assertEqual(
            stream.transcript,
            [
                ("send", expected_request),
                ("end", None),
                ("recv", running),
                ("recv", terminal),
                ("recv", None),
            ],
        )
        self.assertTrue(stream.entered)
        self.assertTrue(stream.exited)
        open_rpc.assert_called_once_with()
