#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, REMAINDER, Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient
from idb.common.misc import get_env_with_idb_prefix
from idb.common.signal import signal_handler_event


class LaunchCommand(TargetCommand):
    @property
    def description(self) -> str:
        return (
            "Launch an application. Will pass through any environment\n"
            "variables prefixed with IDB_"
        )

    @property
    def name(self) -> str:
        return "launch"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "bundle_id", help="Bundle id of the app to launch", type=str
        )
        parser.add_argument(
            "app_arguments",
            help="Arguments to start the app with",
            default=[],
            nargs=REMAINDER,
        )
        parser.add_argument(
            "-f",
            "--foreground-if-running",
            help="If the app is already running foreground that process",
            action="store_true",
        )
        parser.add_argument(
            "-w",
            "--wait-for",
            help="Wait for the process to exit, tailing all output from the app",
            action="store_true",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.launch(
            bundle_id=args.bundle_id,
            args=args.app_arguments,
            env=get_env_with_idb_prefix(),
            foreground_if_running=args.foreground_if_running,
            stop=signal_handler_event("launch") if args.wait_for else None,
        )
