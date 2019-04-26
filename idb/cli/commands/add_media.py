#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class AddMediaCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Add photos/videos to the target"

    @property
    def name(self) -> str:
        return "add-media"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "file_paths", nargs="+", help="Paths to all media files to add"
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.add_media(file_paths=args.file_paths)
