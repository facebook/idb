#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import os
import sys
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.args import find_next_file_prefix, KeyValueDictAppendAction
from idb.common.signal import signal_handler_event
from idb.common.types import (
    Client,
    IdbException,
    ProfileAllProcesses,
    ProfileBundleID,
    ProfileLaunch,
    ProfilePid,
    ProfileTarget,
    TraceProfile,
)
from idb.grpc.xctrace import formatted_time_to_seconds


class XctraceRecordException(IdbException):
    pass


class XctraceRecordCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Record a trace (deprecated: use 'idb profile trace')"

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
            help="Attach and record the process with the given pid, or the running application with the given bundle id",
            metavar="<pid|bundle id>",
            type=str,
        )
        group.add_argument(
            "--launch",
            type=str,
            metavar="<bundle id>",
            help="Launch the installed application with the given bundle id",
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
        print(
            "'idb xctrace record' is deprecated, use 'idb profile trace' instead",
            file=sys.stderr,
        )
        if args.append_run:
            self.logger.info(
                "The '--append-run' option will be ignored. It's not implemented."
            )
        if args.device:
            self.logger.info(
                "The '--device' option will be ignored. The target associated with "
                + "the companion will be used by default."
            )
        if args.stop_timeout:
            self.logger.info("The '--stop-timeout' option will be ignored.")
        unsupported = [
            option
            for option, value in [
                ("--package", args.package),
                ("launch arguments", args.launch_args),
                ("--env", args.env),
                ("--target-stdin", args.target_stdin),
                ("--target-stdout", args.target_stdout),
                ("--post-args", args.post_args),
            ]
            if value
        ]
        if unsupported:
            raise XctraceRecordException(
                f"{', '.join(unsupported)} no longer supported. 'idb profile trace' "
                + "records and exports the trace's tables itself."
            )

        trace_basename = args.output
        if trace_basename:
            if os.path.isdir(trace_basename):
                trace_basename = find_next_file_prefix(
                    os.path.join(trace_basename, "trace"), ["trace"]
                )
            else:
                # remove any user-specified file extension (e.g. 'foo.trace')
                trace_basename = os.path.splitext(trace_basename)[0]
        else:
            trace_basename = find_next_file_prefix("trace", ["trace"])

        result = await client.profile(
            kind=TraceProfile(
                template=args.template,
                duration=formatted_time_to_seconds(args.time_limit),
            ),
            target=_target_from_args(args),
            stop=signal_handler_event("xctrace"),
            artifact_path=f"{trace_basename}.trace",
        )
        print(result.artifact)


def _target_from_args(args: Namespace) -> ProfileTarget:
    if args.launch is not None:
        return ProfileLaunch(bundle_id=args.launch)
    if args.attach is None:
        return ProfileAllProcesses()
    if args.attach.isdigit():
        return ProfilePid(pid=int(args.attach))
    # A bundle id is reverse-DNS, so a value without a dot is a process name from before profile trace.
    if "." not in args.attach:
        raise XctraceRecordException(
            f"--attach no longer accepts a process name, got '{args.attach}'. "
            + "Pass a pid or the running application's bundle id."
        )
    return ProfileBundleID(bundle_id=args.attach)
