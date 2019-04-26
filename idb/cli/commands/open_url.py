#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class OpenUrlCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Open a URL"

    @property
    def name(self) -> str:
        return "open"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("url", help="URL to launch", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.open_url(args.url)
