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
from idb.common.types import Client
from idb.grpc.xctrace import formatted_time_to_seconds


class XctraceRecordException(Exception):
    pass


class XctraceRecordCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Record a trace"

    @property
    def name(self) -> str:
        return "record"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        # Options from official 'xctrace record'
        group = parser.add_mutually_exclusive_group(required=True)
        group.add_argument(
            "--all-processes",
            help="Record all processes",
            action="store_true",
            default=False,
        )
        group.add_argument(
            "--attach",
            help="Attach and record process with the given name or pid",
            metavar="<pid|name>",
            type=str,
        )
        group.add_argument(
            "--launch",
            type=str,
            metavar="command",
            help="Launch process with the given name or path",
        )
        parser.add_argument(
            "--output",
            help="Output .trace file to the given path on the client host",
            type=str,
        )
        parser.add_argument(
            "--append-run",
            help="Not implemented",
            action="store_true",
            default=False,
        )
        parser.add_argument(
            "--template",
            help="Record using given trace template name or path",
            metavar="<path|name>",
            required=True,
            type=str,
        )
        parser.add_argument(
            "--device",
            help="Not implemented",
            metavar="<name|UDID>",
            type=str,
        )
        parser.add_argument(
            "--time-limit",
            help="Limit recording time to the specified value",
            metavar="<time[ms|s|m|h]>",
            type=str,
        )
        parser.add_argument(
            "--package",
            help="Load Instruments Package from given path for duration of the command",
            metavar="<file>",
            type=str,
        )
        parser.add_argument(
            "launch_args",
            nargs="*",
            default=[],
            metavar="argument",
            help="Launch process with the given arguments",
        )
        parser.add_argument(
            "--target-stdin",
            help="Redirect standard input of the launched process",
            metavar="<name>",
            type=str,
        )
        parser.add_argument(
            "--target-stdout",
            help="Redirect standard output of the launched process",
            metavar="<name>",
            type=str,
        )
        parser.add_argument(
            "--env",
            nargs=1,
            default={},
            action=KeyValueDictAppendAction,
            metavar="<VAR=value>",
            help="Set specified environment variable for the launched process",
        )
        # FB options
        parser.add_argument(
            "--stop-timeout",
            metavar="<time[ms|s|m|h]>",
            type=str,
            help="Timeout for stopping the recording",
        )
        parser.add_argument(
            "--post-args",
            nargs="*",
            default=[],
            help="Post processing arguments to process the .trace file",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        if args.append_run:
            self.logger.info(
                "The '--append-run' option will be ignored. It's not implemented."
            )
        if args.device:
            self.logger.info(
                "The '--device' option will be ignored. The target associated with "
                + "the companion will be used by default."
            )
        if args.target_stdin and args.target_stdin != "-":
            raise XctraceRecordException(
                'Only "-" is supported as a valid value for --target-stdin'
            )
        if args.target_stdout and args.target_stdout != "-":
            raise XctraceRecordException(
                'Only "-" is supported as a valid value for --target-stdout'
            )

        env = args.env
        # merge in special environment variables prefixed with 'IDB_'
        env.update(get_env_with_idb_prefix())

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

        result = await client.xctrace_record(
            stop=signal_handler_event("xctrace"),
            output=trace_basename,
            template_name=args.template,
            all_processes=args.all_processes,
            time_limit=formatted_time_to_seconds(args.time_limit),
            package=args.package,
            process_to_attach=args.attach,
            process_to_launch=args.launch,
            process_env=env,
            launch_args=args.launch_args,
            target_stdin=args.target_stdin,
            target_stdout=args.target_stdout,
            post_args=args.post_args,
            stop_timeout=formatted_time_to_seconds(args.stop_timeout),
        )

        print(result)
