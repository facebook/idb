#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class ContactsUpdateCommand(TargetCommand):
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

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.contacts_update(contacts_path=args.contacts_path)
