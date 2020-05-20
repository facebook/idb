#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class MediaAddCommand(ClientCommand):
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
