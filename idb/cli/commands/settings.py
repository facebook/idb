#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.command import CommandGroup
from idb.common.types import Client


_ENABLE = "enable"
_DISABLE = "disable"


class HardwareKeyboardCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Set the hardware keyboard"

    @property
    def name(self) -> str:
        return "hardware-keyboard"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "setting",
            help="Whether to enable or disable the hardware keyboard",
            choices=[_ENABLE, _DISABLE],
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.set_hardware_keyboard(
            enabled=(True if args.setting == _ENABLE else False)
        )


SetCommand = CommandGroup(
    name="set",
    description="Sets a preference on the target",
    commands=[HardwareKeyboardCommand()],
)
