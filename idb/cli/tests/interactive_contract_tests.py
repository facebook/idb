#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import io
from argparse import Namespace
from collections.abc import AsyncIterator
from contextlib import redirect_stdout
from typing import cast
from unittest.mock import AsyncMock, MagicMock, patch

from idb.cli import ClientCommand
from idb.cli.command_tree import build_command_graph, CommandGraph
from idb.cli.commands.dap import StdStreams
from idb.cli.commands.shell import ShellCommand
from idb.common.types import (
    Client,
    CodeCoverageFormat,
    Compression,
    InstalledArtifact,
    TestRunInfo,
)
from idb.utils.testing import TestCase


class _RecordingClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, object]] = []

    async def dap(self, **kwargs: object) -> None:
        self.calls.append(("dap", kwargs))

    async def install_xctest(
        self, xctest: str, skip_signing_bundles: bool | None = None
    ) -> AsyncIterator[InstalledArtifact]:
        self.calls.append(("install_xctest", (xctest, skip_signing_bundles)))
        yield InstalledArtifact(name="InstalledTests", uuid=None, progress=0.0)

    async def install(self, bundle: str) -> AsyncIterator[InstalledArtifact]:
        self.calls.append(("install", bundle))
        names = {
            "App.app": "InstalledApp",
            "Host.app": "InstalledHost",
        }
        yield InstalledArtifact(name=names[bundle], uuid=None, progress=0.0)

    async def run_xctest(self, **kwargs: object) -> AsyncIterator[TestRunInfo]:
        self.calls.append(("run_xctest", kwargs))
        if False:
            yield cast(TestRunInfo, None)


class InteractiveContractTests(TestCase):
    def _resolve(
        self, argv: list[str]
    ) -> tuple[CommandGraph, Namespace, ClientCommand]:
        graph = build_command_graph(extension_loader=lambda: [])
        args = graph.parser.parse_args(argv)
        command = graph.root_command.resolve_command_from_args(args)
        self.assertIsInstance(command, ClientCommand)
        return graph, args, cast(ClientCommand, command)

    async def _run_xctest(
        self, argv: list[str], client: _RecordingClient
    ) -> tuple[dict[str, object], str]:
        _, args, command = self._resolve(argv)
        output = io.StringIO()
        with (
            patch(
                "idb.cli.commands.xctest.get_env_with_idb_prefix",
                return_value={"TOKEN": "value", "EMPTY": ""},
            ),
            redirect_stdout(output),
        ):
            await command.run_with_client(args, cast(Client, client))
        run_calls = [value for name, value in client.calls if name == "run_xctest"]
        self.assertEqual(len(run_calls), 1)
        return cast(dict[str, object], run_calls[0]), output.getvalue()

    def _default_xctest_call(self, **overrides: object) -> dict[str, object]:
        call: dict[str, object] = {
            "test_bundle_id": "Tests",
            "app_bundle_id": None,
            "test_host_app_bundle_id": None,
            "is_ui_test": False,
            "is_logic_test": False,
            "tests_to_run": None,
            "tests_to_skip": None,
            "timeout": None,
            "env": {"TOKEN": "value", "EMPTY": ""},
            "args": [],
            "result_bundle_path": None,
            "report_activities": False,
            "report_attachments": False,
            "activities_output_path": None,
            "coverage_output_path": None,
            "enable_continuous_coverage_collection": False,
            "coverage_format": CodeCoverageFormat.EXPORTED,
            "log_directory_path": None,
            "wait_for_debugger": False,
        }
        call.update(overrides)
        return call

    async def test_dap_plan(self) -> None:
        cases = [
            ("default", ["dap", "opaque/DAP.pkg"], None),
            (
                "zstd",
                ["--compression", "ZSTD", "dap", "opaque/DAP.pkg"],
                Compression.ZSTD,
            ),
        ]
        for name, argv, expected_compression in cases:
            with self.subTest(name=name):
                client = _RecordingClient()
                streams = StdStreams(
                    stdin=asyncio.StreamReader(),
                    stdout=cast(asyncio.StreamWriter, MagicMock()),
                    stderr=cast(asyncio.StreamWriter, MagicMock()),
                )
                stop = asyncio.Event()
                _, args, command = self._resolve(argv)
                with (
                    patch(
                        "idb.cli.commands.dap.get_std_as_streams",
                        new=AsyncMock(return_value=streams),
                    ),
                    patch(
                        "idb.cli.commands.dap.signal_handler_event",
                        return_value=stop,
                    ),
                ):
                    await command.run_with_client(args, cast(Client, client))

                self.assertEqual(len(client.calls), 1)
                call_name, value = client.calls[0]
                self.assertEqual(call_name, "dap")
                call = cast(dict[str, object], value)
                self.assertEqual(call["dap_path"], "opaque/DAP.pkg")
                self.assertIs(call["input_stream"], streams.stdin)
                self.assertIs(call["output_stream"], streams.stdout)
                self.assertIs(call["stop"], stop)
                self.assertEqual(call["compression"], expected_compression)

    async def test_shell_plan(self) -> None:
        for name, argv, expected_no_prompt in [
            ("prompt", ["shell"], False),
            ("no_prompt", ["shell", "--no-prompt"], True),
        ]:
            with self.subTest(name=name):
                graph, args, command = self._resolve(argv)
                self.assertIsInstance(command, ShellCommand)
                shell = cast(ShellCommand, command)
                self.assertIs(shell.parser, graph.parser)
                self.assertIs(shell.root_command, graph.root_command)
                self.assertEqual(args.no_prompt, expected_no_prompt)
                with patch("builtins.input", return_value="exit"):
                    await shell.run_with_client(args, cast(Client, _RecordingClient()))

    async def test_xctest_run_app_plan(self) -> None:
        cases = [
            (
                "default",
                ["xctest", "run", "app", "Tests", "App"],
                self._default_xctest_call(app_bundle_id="App"),
                [],
            ),
            (
                "all_options",
                [
                    "xctest",
                    "run",
                    "app",
                    "--tests-to-run",
                    "Suite/a",
                    "Suite/b",
                    "--tests-to-skip",
                    "Suite/c",
                    "--timeout",
                    "17",
                    "--result-bundle-path",
                    "result.xcresult",
                    "--report-attachments",
                    "--activities-output-path",
                    "activities",
                    "--coverage-output-path",
                    "coverage",
                    "--enable-continuous-coverage-collection",
                    "--coverage-format",
                    "RAW",
                    "--log-directory-path",
                    "logs",
                    "--wait-for-debugger",
                    "Tests",
                    "App",
                    "--flag",
                    "value",
                ],
                self._default_xctest_call(
                    app_bundle_id="App",
                    tests_to_run={"Suite/a", "Suite/b"},
                    tests_to_skip={"Suite/c"},
                    timeout=17,
                    args=["--flag", "value"],
                    result_bundle_path="result.xcresult",
                    report_activities=True,
                    report_attachments=True,
                    activities_output_path="activities",
                    coverage_output_path="coverage",
                    enable_continuous_coverage_collection=True,
                    coverage_format=CodeCoverageFormat.RAW,
                    log_directory_path="logs",
                    wait_for_debugger=True,
                ),
                [],
            ),
            (
                "install",
                [
                    "xctest",
                    "run",
                    "app",
                    "--install",
                    "Tests.xctest",
                    "App.app",
                ],
                self._default_xctest_call(
                    test_bundle_id="InstalledTests",
                    app_bundle_id="InstalledApp",
                ),
                [
                    ("install_xctest", ("Tests.xctest", None)),
                    ("install", "App.app"),
                ],
            ),
        ]
        for name, argv, expected, setup_calls in cases:
            with self.subTest(name=name):
                client = _RecordingClient()
                actual, output = await self._run_xctest(argv, client)
                self.assertEqual(actual, expected)
                self.assertEqual(output, "")
                self.assertEqual(client.calls[:-1], setup_calls)

    async def test_xctest_run_ui_plan(self) -> None:
        cases = [
            (
                "default",
                ["xctest", "run", "ui", "Tests", "App", "Host"],
                self._default_xctest_call(
                    app_bundle_id="App",
                    test_host_app_bundle_id="Host",
                    is_ui_test=True,
                ),
                "",
                [],
            ),
            (
                "debugger",
                [
                    "xctest",
                    "run",
                    "ui",
                    "--wait-for-debugger",
                    "Tests",
                    "App",
                    "Host",
                ],
                self._default_xctest_call(
                    app_bundle_id="App",
                    test_host_app_bundle_id="Host",
                    is_ui_test=True,
                    wait_for_debugger=True,
                ),
                "--wait_for_debugger flag is NOT supported for ui tests. It will default to False\n",
                [],
            ),
            (
                "install",
                [
                    "xctest",
                    "run",
                    "ui",
                    "--install",
                    "Tests.xctest",
                    "App.app",
                    "Host.app",
                ],
                self._default_xctest_call(
                    test_bundle_id="InstalledTests",
                    app_bundle_id="InstalledApp",
                    test_host_app_bundle_id="InstalledHost",
                    is_ui_test=True,
                ),
                "",
                [
                    ("install_xctest", ("Tests.xctest", None)),
                    ("install", "App.app"),
                    ("install", "Host.app"),
                ],
            ),
        ]
        for name, argv, expected, expected_output, setup_calls in cases:
            with self.subTest(name=name):
                client = _RecordingClient()
                actual, output = await self._run_xctest(argv, client)
                self.assertEqual(actual, expected)
                self.assertEqual(output, expected_output)
                self.assertEqual(client.calls[:-1], setup_calls)

    async def test_xctest_run_logic_plan(self) -> None:
        cases = [
            (
                "default",
                ["xctest", "run", "logic", "Tests"],
                None,
            ),
            (
                "legacy_filter",
                [
                    "xctest",
                    "run",
                    "logic",
                    "Tests",
                    "--test-to-run",
                    "Suite/a",
                ],
                {"Suite/a"},
            ),
            (
                "plural_filter",
                [
                    "xctest",
                    "run",
                    "logic",
                    "Tests",
                    "--tests-to-run",
                    "Suite/a",
                    "Suite/b",
                ],
                {"Suite/a,Suite/b"},
            ),
            (
                "legacy_filter_wins",
                [
                    "xctest",
                    "run",
                    "logic",
                    "Tests",
                    "--test-to-run",
                    "Suite/a",
                    "--tests-to-run",
                    "Suite/b",
                    "Suite/c",
                ],
                {"Suite/a"},
            ),
        ]
        for name, argv, expected_tests in cases:
            with self.subTest(name=name):
                client = _RecordingClient()
                actual, output = await self._run_xctest(argv, client)
                self.assertEqual(
                    actual,
                    self._default_xctest_call(
                        is_logic_test=True,
                        tests_to_run=expected_tests,
                    ),
                )
                self.assertEqual(output, "")

        client = _RecordingClient()
        actual, output = await self._run_xctest(
            ["xctest", "run", "logic", "--install", "Tests.xctest"],
            client,
        )
        self.assertEqual(
            actual,
            self._default_xctest_call(
                test_bundle_id="InstalledTests",
                is_logic_test=True,
            ),
        )
        self.assertEqual(output, "")
        self.assertEqual(
            client.calls[:-1],
            [("install_xctest", ("Tests.xctest", None))],
        )
