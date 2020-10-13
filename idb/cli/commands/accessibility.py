#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client


class AccessibilityInfoAllCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Describes Accessibility Information for the entire screen"

    @property
    def name(self) -> str:
        return "describe-all"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "--nested",
            help="Will report data in the newer nested format, rather than the flat one",
            action="store_true",
            default=False,
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        info = await client.accessibility_info(point=None, nested=args.nested)
        print(info.json)


class AccessibilityInfoAtPointCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Describes Accessibility Information at a point on the screen"

    @property
    def name(self) -> str:
        return "describe-point"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "--nested",
            help="Will report data in the newer nested format, rather than the flat one",
            action="store_true",
            default=False,
        )
        parser.add_argument("x", help="The x-coordinate", type=int)
        parser.add_argument("y", help="The y-coordinate", type=int)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        info = await client.accessibility_info(
            point=(args.x, args.y), nested=args.nested
        )
        print(info.json)
