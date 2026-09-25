#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import io
from argparse import Namespace
from contextlib import redirect_stdout
from typing import cast
from unittest.mock import AsyncMock, patch

from idb.cli import CompanionCommand
from idb.cli.command_tree import build_command_graph
from idb.common.types import Companion
from idb.utils.testing import TestCase


class _WaitEvent:
    def __init__(self) -> None:
        self.wait = AsyncMock()


class _HeadlessBootContext:
    def __init__(self) -> None:
        self.entered = False
        self.exited = False

    async def __aenter__(self) -> None:
        self.entered = True

    async def __aexit__(self, *_args: object) -> None:
        self.exited = True


class _HeadlessBootCompanion:
    def __init__(self) -> None:
        self.boot_headless_calls: list[str] = []
        self.boot_calls: list[str] = []
        self.context = _HeadlessBootContext()

    def boot_headless(self, udid: str) -> _HeadlessBootContext:
        self.boot_headless_calls.append(udid)
        return self.context

    async def boot(self, udid: str) -> None:
        self.boot_calls.append(udid)


class Wave9ContractTests(TestCase):
    def _resolve(self, argv: list[str]) -> tuple[Namespace, CompanionCommand]:
        graph = build_command_graph(extension_loader=lambda: [])
        args = graph.parser.parse_args(argv)
        command = graph.root_command.resolve_command_from_args(args)
        self.assertIsInstance(command, CompanionCommand)
        return args, cast(CompanionCommand, command)

    async def test_boot_headless_plan(self) -> None:
        udid = "0B3311FA-234C-4665-950F-37544F690B61"
        cases = [
            ("positional_udid", ["boot", "--headless", udid]),
            ("legacy_udid_flag", ["boot", "--headless", "--udid", udid]),
        ]
        for name, argv in cases:
            with self.subTest(name=name):
                companion = _HeadlessBootCompanion()
                event = _WaitEvent()
                stdout = io.StringIO()
                with (
                    patch(
                        "idb.cli.commands.target.signal_handler_event",
                        return_value=event,
                    ) as signal_handler_event,
                    redirect_stdout(stdout),
                ):
                    args, command = self._resolve(argv)
                    await command.run_with_companion(args, cast(Companion, companion))

                self.assertEqual(companion.boot_headless_calls, [udid])
                self.assertTrue(companion.context.entered)
                self.assertTrue(companion.context.exited)
                self.assertEqual(companion.boot_calls, [])
                signal_handler_event.assert_called_once_with("headless_boot")
                event.wait.assert_awaited_once_with()
                self.assertEqual(stdout.getvalue(), "")
