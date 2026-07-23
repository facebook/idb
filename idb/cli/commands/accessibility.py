#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import (
    ACCESSIBILITY_KEY_BY_NAME,
    AccessibilityMarker,
    AccessibilityPoint,
    Client,
)


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
        info = await client.accessibility_info(target=None, nested=args.nested)
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
            target=AccessibilityPoint(x=args.x, y=args.y), nested=args.nested
        )
        print(info.json)


class AccessibilityDescribeMarkerCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Describe the accessibility element matching a marker"

    @property
    def name(self) -> str:
        return "describe"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "marker",
            help="Marker matched (substring) against the element's --match-key",
        )
        parser.add_argument(
            "--match-key",
            choices=list(ACCESSIBILITY_KEY_BY_NAME),
            default="AXLabel",
            help="Accessibility key to match the marker against",
        )
        parser.add_argument(
            "--depth", type=int, default=10, help="Maximum tree depth to search"
        )
        parser.add_argument(
            "--nested",
            action="store_true",
            default=False,
            help="Report data in the nested format rather than the flat one",
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        info = await client.accessibility_info(
            target=AccessibilityMarker(
                value=args.marker,
                match_key=ACCESSIBILITY_KEY_BY_NAME[args.match_key],
                depth=args.depth,
            ),
            nested=args.nested,
        )
        print(info.json)
