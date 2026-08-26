#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.command import CommandGroup
from idb.common.types import Client


class SetPreferenceCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Sets a preference"

    @property
    def name(self) -> str:
        return "set"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--domain",
            type=str,
            default=None,
            help="Preference domain, assumed to be Apple Global Domain if not specified",
        )
        parser.add_argument(
            "name",
            help="Preference name",
            type=str,
        )
        parser.add_argument(
            "--type",
            help="Specifies the type of the value to be set, for supported types see 'defaults get help' defaults to string. "
            "Example of usage: idb set --domain com.apple.suggestions.plist SuggestionsAppLibraryEnabled --type bool true",
            type=str,
            default="string",
        )
        parser.add_argument(
            "value",
            help="Preference value",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.set_preference(
            name=args.name,
            value=args.value,
            value_type=args.type,
            domain=args.domain,
        )


class GetPreferenceCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Gets a preference value"

    @property
    def name(self) -> str:
        return "get"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--domain",
            type=str,
            default=None,
            help="Preference domain, assumed to be Apple Global Domain if not specified",
        )
        parser.add_argument(
            "name",
            help="Preference name",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        value = await client.get_preference(name=args.name, domain=args.domain)
        print(value)


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


ListCommand = CommandGroup(
    name="list",
    description="Lists values from the target",
    commands=[ListLocaleCommand()],
)
