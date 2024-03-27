#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from argparse import ArgumentParser, Namespace, REMAINDER

from idb.cli import ClientCommand
from idb.common.misc import get_env_with_idb_prefix
from idb.common.signal import signal_handler_event
from idb.common.types import Client


class LaunchCommand(ClientCommand):
    @property
    def description(self) -> str:
        return (
            "Launch an application. Any environment variables of the form IDB_X\n"
            " will be passed through with the IDB_ prefix removed."
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
            "-d",
            "--wait-for-debugger",
            help="Suspend application right after the launch to facilitate attaching of a debugger (ex, lldb).",
            action="store_true",
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
        parser.add_argument(
            "-p",
            "--pid-file",
            help="launched app pid will be written into the specified file",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.launch(
            bundle_id=args.bundle_id,
            args=args.app_arguments,
            env=get_env_with_idb_prefix(),
            foreground_if_running=args.foreground_if_running,
            wait_for_debugger=args.wait_for_debugger,
            stop=signal_handler_event("launch") if args.wait_for else None,
            pid_file=args.pid_file,
        )
