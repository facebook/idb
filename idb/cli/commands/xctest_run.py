#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, REMAINDER, Namespace
from typing import List, Optional, Set

from idb.cli.commands.base import Command, CompositeCommand, TargetCommand
from idb.client.client import IdbClient
from idb.common.format import human_format_test_info, json_format_test_info
from idb.common.misc import get_env_with_idb_prefix


class CommonRunXcTestCommand(TargetCommand):
    @property
    def description(self) -> str:
        return (
            f"Run an installed {self.name} test. Will pass through"
            " any environment\nvariables prefixed with IDB_"
        )

    def add_parser_positional_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "test_bundle_id", help="Bundle id of the test to launch", type=str
        )

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        self.add_parser_positional_arguments(parser)
        parser.add_argument(
            "--result-bundle-path",
            default=None,
            type=str,
            help="Path to save the result bundle",
        )
        parser.add_argument(
            "--timeout", help="Seconds before timeout occurs", default=3600, type=int
        )
        parser.add_argument(
            "test_arguments",
            help="Arguments to start the test with",
            default=[],
            nargs=REMAINDER,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await super().run_with_client(args, client)
        tests_to_run = self.get_tests_to_run(args)
        tests_to_skip = self.get_tests_to_skip(args)
        app_bundle_id = args.app_bundle_id if hasattr(args, "app_bundle_id") else None
        test_host_app_bundle_id = (
            args.test_host_app_bundle_id
            if hasattr(args, "test_host_app_bundle_id")
            else None
        )
        is_ui = args.run == "ui"
        is_logic = args.run == "logic"

        formatter = json_format_test_info if args.json else human_format_test_info
        async for test_result in client.run_xctest(
            test_bundle_id=args.test_bundle_id,
            app_bundle_id=app_bundle_id,
            test_host_app_bundle_id=test_host_app_bundle_id,
            is_ui_test=is_ui,
            is_logic_test=is_logic,
            tests_to_run=tests_to_run,
            tests_to_skip=tests_to_skip,
            timeout=args.timeout,
            env=get_env_with_idb_prefix(),
            args=args.test_arguments,
            result_bundle_path=args.result_bundle_path,
        ):
            print(formatter(test_result))

    def get_tests_to_run(self, args: Namespace) -> Optional[Set[str]]:
        return None

    def get_tests_to_skip(self, args: Namespace) -> Optional[Set[str]]:
        return None


class RunXcTestAppCommand(CommonRunXcTestCommand):
    @property
    def name(self) -> str:
        return "app"

    def add_parser_positional_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_positional_arguments(parser)
        parser.add_argument(
            "app_bundle_id", help="Bundle id of the app to test", type=str
        )

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "--tests-to-run",
            nargs="*",
            help="Run only these tests, \
            if not specified all tests are run. \
            Format: className/methodName",
        )
        parser.add_argument(
            "--tests-to-skip",
            nargs="*",
            help="Skip these tests, \
            has precedence over --tests-to-run. \
            Format: className/methodName",
        )

    def get_tests_to_run(self, args: Namespace) -> Optional[Set[str]]:
        return set(args.tests_to_run) if args.tests_to_run else None

    def get_tests_to_skip(self, args: Namespace) -> Optional[Set[str]]:
        return set(args.tests_to_skip) if args.tests_to_skip else None


class RunXcTestUICommand(RunXcTestAppCommand):
    @property
    def name(self) -> str:
        return "ui"

    def add_parser_positional_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_positional_arguments(parser)
        parser.add_argument(
            "test_host_app_bundle_id",
            help="Bundle id of the app that hosts ui test",
            type=str,
        )


class RunXcTestLogicCommand(CommonRunXcTestCommand):
    @property
    def name(self) -> str:
        return "logic"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "--test-to-run",
            nargs=1,
            help="Run only this test, \
            if not specified all tests are run. \
            Format: className",
        )

    def get_tests_to_run(self, args: Namespace) -> Optional[Set[str]]:
        return set(args.test_to_run) if args.test_to_run else None


class RunXctestCommand(CompositeCommand):
    def __init__(self) -> None:
        self._subcommands: List[Command] = [
            RunXcTestAppCommand(),
            RunXcTestUICommand(),
            RunXcTestLogicCommand(),
        ]

    @property
    def subcommands(self) -> List[Command]:
        return self._subcommands

    @property
    def description(self) -> str:
        return (
            "Run an installed xctest. Will pass through any environment\n"
            "variables prefixed with IDB_"
        )

    @property
    def name(self) -> str:
        return "run"

    async def run(self, args: Namespace, context: Optional[Namespace] = None) -> None:
        await super().run(args, context)  # pyre-ignore

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await self.run(args)
