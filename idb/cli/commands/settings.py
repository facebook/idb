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


class SetHardwareKeyboardCommand(ClientCommand):
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


class SetLocaleCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Sets the locale of the simulator"

    @property
    def name(self) -> str:
        return "locale"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "locale_identifier",
            help="The locale identifier",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.set_locale(
            locale_identifier=args.locale_identifier,
        )


class GetLocaleCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Gets the locale of the simulator"

    @property
    def name(self) -> str:
        return "locale"

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        locale_identifier = await client.get_locale()
        print(locale_identifier)


class ListLocaleCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Lists available locale identifiers"

    @property
    def name(self) -> str:
        return "locale"

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        locale_identifiers = await client.list_locale_identifiers()
        for locale_identifier in locale_identifiers:
            print(locale_identifier)


SetCommand = CommandGroup(
    name="set",
    description="Sets a preference on the target",
    commands=[SetHardwareKeyboardCommand(), SetLocaleCommand()],
)

GetCommand = CommandGroup(
    name="get",
    description="Gets a value from the target",
    commands=[GetLocaleCommand()],
)

ListCommand = CommandGroup(
    name="list",
    description="Lists values from the target",
    commands=[ListLocaleCommand()],
)
