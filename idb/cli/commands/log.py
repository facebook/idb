#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import REMAINDER, ArgumentParser, Namespace
from typing import List, Optional

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import IdbClient


class LogCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Obtain logs from the target"

    @property
    def name(self) -> str:
        return "log"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "log_arguments",
            help="""\
Example: idb log -- --style json
Possible arguments:
--system | --process (pid|process) | --parent (pid|process) ]
    [ --level default|info|debug][ --predicate <predicate> ]
    [ --source ][ --style (syslog|json) ]
    [ --timeout <num>[m|h|d] ][ --type activity|log|trace ]

Examples:
log stream --level=info
log stream --predicate examples:
    --predicate 'eventMessage contains "my message"'
    --predicate 'eventType == logEvent and messageType == info'
    --predicate 'processImagePath endswith "d"'
    --predicate 'not processImagePath contains[c] "some spammer"'
    --predicate 'processID < 100'
    --predicate 'senderImagePath beginswith "my sender"'""",
            default=[],
            nargs=REMAINDER,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        async for chunk in client.tail_logs(
            stop=signal_handler_event("log"),
            arguments=self.normalise_log_arguments(args.log_arguments),
        ):
            print(chunk, end="")
        print("")

    def normalise_log_arguments(
        self, log_arguments: Optional[List[str]]
    ) -> Optional[List[str]]:
        if log_arguments is None:
            return None

        if len(log_arguments) > 0 and log_arguments[0] == "--":
            log_arguments = log_arguments[1:]

        return log_arguments


class CompanionLogCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Obtain logs from the companion"

    @property
    def name(self) -> str:
        return "log"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        async for chunk in client.tail_companion_logs(stop=signal_handler_event("log")):
            print(chunk, end="")
        print("")
