#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import shlex
import sys
from argparse import ArgumentParser, Namespace
from typing import Optional

from idb.cli import ClientCommand
from idb.common.command import CommandGroup
from idb.common.types import Client
from idb.common.types import IdbException
from idb.utils.typing import none_throws


class ShellCommand(ClientCommand):
    def __init__(self, parser: ArgumentParser) -> None:
        super().__init__()
        self.parser = parser
        self.root_command: Optional[CommandGroup] = None

    @property
    def description(self) -> str:
        return "Interactive shell"

    @property
    def name(self) -> str:
        return "shell"

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        # Setup
        root_command = none_throws(self.root_command)
        last_success = True
        # Prompt loop
        while True:
            sys.stdout.flush()
            sys.stderr.flush()
            new_args = shlex.split(input("idb> "))
            # Special shell commands
            if new_args == ["exit"]:
                return
            elif new_args == ["last_success"]:
                print("1" if last_success else "0")
                continue
            # Run the specified command
            try:
                args = self.parser.parse_args(new_args)
                command = root_command.resolve_command_from_args(args)
                if not isinstance(command, ClientCommand):
                    print("shell commands must be client commands", file=sys.stderr)
                    continue
                await command.run_with_client(args, client)
                last_success = True
            except IdbException as e:
                print(e.args[0], file=sys.stderr)
                last_success = False
