#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import io
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from typing import cast

from idb.cli import CompanionCommand, ManagementCommand
from idb.cli.command_tree import build_command_graph
from idb.cli.commands.target import ConnectCommandException
from idb.common.types import (
    ClientManager,
    Companion,
    CompanionInfo,
    ConnectionDestination,
    IdbException,
    OnlyFilter,
    TargetDescription,
    TargetType,
    TCPAddress,
)
from idb.utils.testing import TestCase


class _Manager:
    def __init__(
        self,
        *,
        connection: CompanionInfo | None = None,
        targets: list[TargetDescription] | None = None,
        connect_error: IdbException | None = None,
    ) -> None:
        self.connection = connection
        self.targets = targets or []
        self.connect_error = connect_error
        self.calls: list[tuple[str, object]] = []

    async def connect(self, destination: ConnectionDestination) -> CompanionInfo:
        self.calls.append(("connect", destination))
        if self.connect_error is not None:
            raise self.connect_error
        assert self.connection is not None
        return self.connection

    async def list_targets(
        self, only: OnlyFilter | None = None
    ) -> list[TargetDescription]:
        self.calls.append(("list_targets", only))
        return self.targets


class _LifecycleCompanion:
    def __init__(self, result: TargetDescription) -> None:
        self.result = result
        self.calls: list[tuple[str, object]] = []

    async def create(self, device_type: str, os_version: str) -> TargetDescription:
        self.calls.append(("create", (device_type, os_version)))
        return self.result

    async def boot(self, udid: str) -> None:
        self.calls.append(("boot", udid))

    async def shutdown(self, udid: str) -> None:
        self.calls.append(("shutdown", udid))

    async def erase(self, udid: str) -> None:
        self.calls.append(("erase", udid))

    async def clone(self, udid: str) -> TargetDescription:
        self.calls.append(("clone", udid))
        return self.result

    async def delete(self, udid: str | None) -> None:
        self.calls.append(("delete", udid))


class Wave9OutputTests(TestCase):
    def _resolve_management(
        self, argv: list[str]
    ) -> tuple[Namespace, ManagementCommand]:
        graph = build_command_graph(extension_loader=lambda: [])
        args = graph.parser.parse_args(argv)
        command = graph.root_command.resolve_command_from_args(args)
        self.assertIsInstance(command, ManagementCommand)
        return args, cast(ManagementCommand, command)

    def _resolve_companion(self, argv: list[str]) -> tuple[Namespace, CompanionCommand]:
        graph = build_command_graph(extension_loader=lambda: [])
        args = graph.parser.parse_args(argv)
        command = graph.root_command.resolve_command_from_args(args)
        self.assertIsInstance(command, CompanionCommand)
        return args, cast(CompanionCommand, command)

    async def _capture_management(
        self, argv: list[str], manager: _Manager
    ) -> tuple[str, str]:
        args, command = self._resolve_management(argv)
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            await command.run_with_manager(args, cast(ClientManager, manager))
        return stdout.getvalue(), stderr.getvalue()

    async def _capture_companion(
        self, argv: list[str], companion: _LifecycleCompanion
    ) -> tuple[str, str]:
        args, command = self._resolve_companion(argv)
        stdout = io.StringIO()
        stderr = io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            await command.run_with_companion(args, cast(Companion, companion))
        return stdout.getvalue(), stderr.getvalue()

    async def test_connect_human_json_and_typed_error_output(self) -> None:
        host = "127.0.0.1"
        port = 10882
        response = CompanionInfo(
            udid="connected-udid",
            is_local=False,
            pid=123,
            address=TCPAddress(host=host, port=port),
            metadata={"source": "test"},
        )
        success_cases = [
            (
                "human",
                ["connect", host, str(port)],
                "udid: connected-udid is_local: False\n",
            ),
            (
                "json",
                ["connect", host, str(port), "--json"],
                '{"udid": "connected-udid", "is_local": false, "metadata": {"source": "test"}}\n',
            ),
        ]
        for name, argv, expected_stdout in success_cases:
            with self.subTest(name=name):
                manager = _Manager(connection=response)
                stdout, stderr = await self._capture_management(argv, manager)
                self.assertEqual(stdout, expected_stdout)
                self.assertEqual(stderr, "")
                self.assertEqual(
                    manager.calls,
                    [("connect", TCPAddress(host=host, port=port))],
                )

        failure_cases = [
            ("human", ["connect", host, str(port)]),
            ("json_flag", ["connect", host, str(port), "--json"]),
        ]
        for name, argv in failure_cases:
            with self.subTest(name=f"typed_failure_{name}"):
                manager = _Manager(connect_error=IdbException("wire failure"))
                stdout = io.StringIO()
                stderr = io.StringIO()
                args, command = self._resolve_management(argv)
                with (
                    redirect_stdout(stdout),
                    redirect_stderr(stderr),
                    self.assertRaises(ConnectCommandException) as raised,
                ):
                    await command.run_with_manager(args, cast(ClientManager, manager))

                self.assertEqual(
                    str(raised.exception),
                    "Could not connect to 127.0.0.1:10882.\n"
                    "            Make sure both host and port are correct and reachable",
                )
                self.assertEqual(stdout.getvalue(), "")
                self.assertEqual(stderr.getvalue(), "")
                self.assertEqual(
                    manager.calls,
                    [("connect", TCPAddress(host=host, port=port))],
                )

    async def test_list_targets_human_json_empty_sorted_and_filter_output(
        self,
    ) -> None:
        alpha = TargetDescription(
            udid="alpha-udid",
            name="Alpha",
            target_type=TargetType.SIMULATOR,
            state="Shutdown",
            os_version="iOS 17.0",
            architecture="arm64",
            companion_info=None,
            screen_dimensions=None,
        )
        zulu = TargetDescription(
            udid="zulu-udid",
            name="Zulu",
            target_type=TargetType.DEVICE,
            state="Booted",
            os_version="iOS 18.0",
            architecture="arm64",
            companion_info=CompanionInfo(
                udid="zulu-udid",
                is_local=False,
                pid=456,
                address=TCPAddress(host="remote.example", port=10882),
            ),
            screen_dimensions=None,
        )
        cases = [
            (
                "human_empty",
                ["list-targets"],
                [],
                None,
                "No available targets\n",
            ),
            ("json_empty", ["list-targets", "--json"], [], None, ""),
            (
                "human_sorted",
                ["list-targets"],
                [zulu, alpha],
                None,
                "Alpha | alpha-udid | Shutdown | simulator | iOS 17.0 | arm64 | No Companion Connected\n"
                "Zulu | zulu-udid | Booted | device | iOS 18.0 | arm64 | remote.example:10882\n",
            ),
            (
                "json_sorted",
                ["list-targets", "--json"],
                [zulu, alpha],
                None,
                '{"name": "Alpha", "udid": "alpha-udid", "state": "Shutdown", "type": "simulator", "os_version": "iOS 17.0", "architecture": "arm64"}\n'
                '{"name": "Zulu", "udid": "zulu-udid", "state": "Booted", "type": "device", "os_version": "iOS 18.0", "architecture": "arm64", "host": "remote.example", "port": 10882, "is_local": false, "companion": "remote.example:10882"}\n',
            ),
            (
                "filter_forwarded",
                ["list-targets", "--only", "simulator"],
                [],
                TargetType.SIMULATOR,
                "No available targets\n",
            ),
        ]
        for name, argv, targets, expected_only, expected_stdout in cases:
            with self.subTest(name=name):
                manager = _Manager(targets=targets)
                stdout, stderr = await self._capture_management(argv, manager)
                self.assertEqual(stdout, expected_stdout)
                self.assertEqual(stderr, "")
                self.assertEqual(manager.calls, [("list_targets", expected_only)])

    async def test_local_lifecycle_udid_and_silent_output(self) -> None:
        source_udid = "source-udid"
        result = TargetDescription(
            udid="result-udid",
            name="Result",
            target_type=TargetType.SIMULATOR,
            state="Shutdown",
            os_version="iOS 17.0",
            architecture="arm64",
            companion_info=None,
            screen_dimensions=None,
        )
        cases = [
            (
                "create_udid",
                ["create", "iPhone 15", "iOS 17.0"],
                ("create", ("iPhone 15", "iOS 17.0")),
                "result-udid\n",
            ),
            ("boot_silent", ["boot", source_udid], ("boot", source_udid), ""),
            (
                "shutdown_silent",
                ["shutdown", source_udid],
                ("shutdown", source_udid),
                "",
            ),
            ("erase_silent", ["erase", source_udid], ("erase", source_udid), ""),
            (
                "clone_udid",
                ["clone", source_udid],
                ("clone", source_udid),
                "result-udid\n",
            ),
            (
                "delete_silent",
                ["delete", source_udid],
                ("delete", source_udid),
                "",
            ),
            ("delete_all_silent", ["delete-all"], ("delete", None), ""),
        ]
        for name, argv, expected_call, expected_stdout in cases:
            with self.subTest(name=name):
                companion = _LifecycleCompanion(result)
                stdout, stderr = await self._capture_companion(argv, companion)
                self.assertEqual(stdout, expected_stdout)
                self.assertEqual(stderr, "")
                self.assertEqual(companion.calls, [expected_call])
