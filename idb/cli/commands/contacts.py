#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client


class ContactsUpdateCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Updates the contacts"

    @property
    def name(self) -> str:
        return "update"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "contacts_path",
            help="Path to the directory containing contacts sqlite databases",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.contacts_update(contacts_path=args.contacts_path)
