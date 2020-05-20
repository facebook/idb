#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.args import KeyValueDictAppendAction, find_next_file_prefix
from idb.common.misc import get_env_with_idb_prefix
from idb.common.signal import signal_handler_event
from idb.common.types import IdbClient, InstrumentsTimings


class InstrumentsCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Run instruments on the device"

    @property
    def name(self) -> str:
        return "instruments"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--template",
            help="Template to run (see Apple for possible values)",
            required=True,
            type=str,
        )
        parser.add_argument(
            "--app-bundle-id", help="App to run instruments on", type=str
        )
        parser.add_argument(
            "--app-args",
            nargs="*",
            default=[],
            help="Arguments to be passed to the app being profiled",
        )
        parser.add_argument(
            "--app-env",
            nargs=1,
            default={},
            action=KeyValueDictAppendAction,
            metavar="KEY=VALUE",
            help="Environment key/value pairs for the app being profiled",
        )
        parser.add_argument(
            "--output",
            help="Output path / base name where the trace file will be saved",
            type=str,
        )
        parser.add_argument(
            "--post-args",
            nargs="*",
            default=[],
            help="Post processing arguments to process the Instruments trace",
        )
        parser.add_argument(
            "--operation-duration",
            help=(
                "The maximum running time for Instruments. Instruments will "
                + "terminate automatically afterwards"
            ),
            type=float,
        )
        parser.add_argument(
            "--terminate-timeout",
            help="The maximum time to terminate Instruments",
            type=float,
        )
        parser.add_argument(
            "--launch-retry-timeout",
            help=(
                "If Instruments fails to start, IDB will try to launch it "
                + "again. This is the total time for the entire retry process"
            ),
            type=float,
        )
        parser.add_argument(
            "--launch-error-timeout",
            help=(
                "The wait time for the Instruments error message to occur. "
                + "If it did not appear during this timeout, IDB will assume "
                + "that Instruments started properly"
            ),
            type=float,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        app_arguments = args.app_args

        app_environment = args.app_env
        # merge in special environment variables prefixed with 'IDB_'
        app_environment.update(get_env_with_idb_prefix())

        post_process_arguments = args.post_args

        timings = (
            InstrumentsTimings(
                terminate_timeout=args.terminate_timeout,
                launch_retry_timeout=args.launch_retry_timeout,
                launch_error_timeout=args.launch_error_timeout,
                operation_duration=args.operation_duration,
            )
            if (
                args.terminate_timeout
                or args.launch_retry_timeout
                or args.launch_error_timeout
                or args.operation_duration
            )
            else None
        )

        trace_extensions = ["trace"]
        trace_basename = args.output
        if trace_basename:
            if os.path.isdir(trace_basename):
                trace_basename = find_next_file_prefix(
                    os.path.join(trace_basename, "trace"), trace_extensions
                )
            else:
                # remove any user-specified file extension (e.g. 'foo.trace')
                trace_basename = os.path.splitext(trace_basename)[0]
        else:
            trace_basename = find_next_file_prefix("trace", trace_extensions)

        result = await client.run_instruments(
            stop=signal_handler_event("instruments"),
            trace_basename=trace_basename,
            template_name=args.template,
            app_bundle_id=args.app_bundle_id,
            app_environment=app_environment,
            app_arguments=app_arguments,
            tool_arguments=None,
            timings=timings,
            post_process_arguments=post_process_arguments,
        )

        print(result)
