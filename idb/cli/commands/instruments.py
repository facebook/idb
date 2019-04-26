#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient
from idb.common.misc import get_env_with_idb_prefix
from idb.common.signal import signal_handler_event


class InstrumentsCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Run instruments on the device"

    @property
    def name(self) -> str:
        return "instruments"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "template", help="Template to run (see Apple for possible values)", type=str
        )
        parser.add_argument(
            "--app-bundle-id", help="App to run instruments on (Unsupported)", type=str
        )
        parser.add_argument(
            "--trace-path", help="Path where the trace file will be saved", type=str
        )
        parser.add_argument(
            "--post-args",
            nargs="*",
            help="Post processing arguments to process the Instruments trace",
        )
        parser.add_argument(
            "--app-args",
            nargs="*",
            help="Arguments to be passed to the app being profiled",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        trace_path = args.trace_path
        if trace_path is None:
            trace_path = f"{args.template}.trace"
        app_args = None if not args.app_args else args.app_args
        post_process_arguments = None if not args.post_args else args.post_args
        result = await client.run_instruments(
            stop=signal_handler_event("instruments"),
            template=args.template,
            app_bundle_id=args.app_bundle_id,
            post_process_arguments=post_process_arguments,
            env=get_env_with_idb_prefix(),
            app_args=app_args,
            trace_path=trace_path,
        )
        print(result)
