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
    AccessibilityScrollDirection,
    AccessibilitySearchableKey,
    AccessibilityTarget,
    Client,
    IdbException,
)


def _looks_int(value: str) -> bool:
    try:
        int(value)
        return True
    except ValueError:
        return False


def _parse_target(
    tokens: list[str], match_key: AccessibilitySearchableKey, depth: int
) -> AccessibilityTarget | None:
    """Interpret positional tokens as an accessibility target: 'x y' coordinates
    (a point), a single marker string, or nothing (the frontmost app). Two integer
    tokens are always read as coordinates, so quote a marker that would otherwise
    look like a coordinate pair (e.g. "42 7")."""
    if len(tokens) == 2 and _looks_int(tokens[0]) and _looks_int(tokens[1]):
        return AccessibilityPoint(x=int(tokens[0]), y=int(tokens[1]))
    if len(tokens) == 1:
        return AccessibilityMarker(value=tokens[0], match_key=match_key, depth=depth)
    if not tokens:
        return None
    raise IdbException(
        "expected 'x y' coordinates, a single marker string, or no target "
        "for the frontmost app"
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


class AccessibilityScrollCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Scroll an accessibility element (or the frontmost app)"

    @property
    def name(self) -> str:
        return "scroll"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "direction",
            choices=[d.name.lower() for d in AccessibilityScrollDirection],
            help="Scroll direction",
        )
        parser.add_argument(
            "target",
            nargs="*",
            help="Optional 'x y' coordinates or a single marker; omit to target "
            "the frontmost app. Two integers are read as coordinates — quote a "
            "marker that looks like a coordinate pair.",
        )
        parser.add_argument(
            "--match-key",
            choices=list(ACCESSIBILITY_KEY_BY_NAME),
            default="AXLabel",
            help="Accessibility key to match a marker against",
        )
        parser.add_argument(
            "--depth", type=int, default=10, help="Maximum tree depth to search"
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        target = _parse_target(
            args.target,
            match_key=ACCESSIBILITY_KEY_BY_NAME[args.match_key],
            depth=args.depth,
        )
        await client.accessibility_scroll(
            target=target,
            direction=AccessibilityScrollDirection[args.direction.upper()],
        )


class AccessibilitySetValueCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Set the accessibility value of an element"

    @property
    def name(self) -> str:
        return "set-value"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "target",
            nargs="+",
            help="'x y' coordinates or a single marker string",
        )
        parser.add_argument("--value", required=True, help="The value to set")
        parser.add_argument(
            "--match-key",
            choices=list(ACCESSIBILITY_KEY_BY_NAME),
            default="AXLabel",
            help="Accessibility key to match a marker against",
        )
        parser.add_argument(
            "--depth", type=int, default=10, help="Maximum tree depth to search"
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        target = _parse_target(
            args.target,
            match_key=ACCESSIBILITY_KEY_BY_NAME[args.match_key],
            depth=args.depth,
        )
        if target is None:
            raise IdbException("set-value requires 'x y' coordinates or a marker")
        await client.accessibility_set_value(target=target, value=args.value)
