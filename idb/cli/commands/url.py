#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class UrlOpenCommand(ClientCommand):
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
