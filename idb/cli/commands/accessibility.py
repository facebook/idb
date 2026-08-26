#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
import sys
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import (
    ACCESSIBILITY_BACKEND_BY_NAME,
    ACCESSIBILITY_FORMAT_BY_NAME,
    ACCESSIBILITY_KEY_BY_NAME,
    AccessibilityBackend,
    AccessibilityInfoOptions,
    AccessibilityMarker,
    AccessibilityOutputFormat,
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


def _add_enricher_args(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--key",
        action="append",
        dest="keys",
        default=None,
        help="Accessibility key to include (repeatable); all keys if omitted",
    )
    parser.add_argument(
        "--profile",
        action="store_true",
        default=False,
        help=(
            "Collect element counts and timings for the read. Reported by "
            "--format complete only; the other formats collect but have "
            "nowhere to report, so their output is unchanged."
        ),
    )
    parser.add_argument(
        "--collect-frame-coverage",
        action="store_true",
        default=False,
        help=(
            "Collect upper-region frame coverage for the read. Reported by "
            "--format complete only, like --profile."
        ),
    )


def _add_backend_arg(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--api",
        choices=list(ACCESSIBILITY_BACKEND_BY_NAME),
        default=None,
        help=(
            "Which backend serves the read (default: the companion's standard "
            "accessibility backend). axbridge spawns a guest reader per read; "
            "axbridge-persistent keeps that reader alive on the companion for "
            "fast repeated reads. A companion that predates backend selection "
            "ignores this and serves the default backend."
        ),
    )


def _backend(args: Namespace) -> AccessibilityBackend | None:
    api = getattr(args, "api", None)
    return ACCESSIBILITY_BACKEND_BY_NAME[api] if api else None


def _add_format_arg(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--format",
        dest="format",
        choices=list(ACCESSIBILITY_FORMAT_BY_NAME),
        default=None,
        help=(
            "Output format: default (the flat element array), nested (each "
            "element carries its children), or complete (a consolidated "
            "document that also reports which backend served the read, the "
            "target, screen bounds, truncation and any blocking modal). "
            "--nested is a deprecated alias for --format nested. A companion "
            "that predates format selection returns the default format; "
            "requesting complete against one prints a warning."
        ),
    )


def _format(args: Namespace) -> AccessibilityOutputFormat | None:
    name = getattr(args, "format", None)
    if name is None:
        return None
    if args.nested:
        raise IdbException(
            "--nested is a deprecated alias for --format nested; pass one or the other"
        )
    return ACCESSIBILITY_FORMAT_BY_NAME[name]


def _warn_if_complete_downgraded(
    requested: AccessibilityOutputFormat | None, payload: str
) -> None:
    # The complete document is an object naming the backend that served it; a
    # legacy-shaped response to a COMPLETE request means the companion ignored
    # the unknown format value — the one silent skew case, surfaced here.
    if requested != AccessibilityOutputFormat.COMPLETE:
        return
    try:
        document = json.loads(payload)
    except json.JSONDecodeError:
        return
    if isinstance(document, dict) and "backend" in document:
        return
    print(
        "warning: the companion does not support --format complete (it "
        "predates format selection); the read was served in the legacy "
        "format by the default backend",
        file=sys.stderr,
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
        _add_enricher_args(parser)
        _add_backend_arg(parser)
        _add_format_arg(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        requested_format = _format(args)
        info = await client.accessibility_info(
            target=None,
            options=AccessibilityInfoOptions(
                nested=args.nested,
                keys=args.keys,
                backend=_backend(args),
                format=requested_format,
                profile=args.profile,
                collect_frame_coverage=args.collect_frame_coverage,
            ),
        )
        _warn_if_complete_downgraded(requested_format, info.json)
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
        _add_enricher_args(parser)
        _add_backend_arg(parser)
        _add_format_arg(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        requested_format = _format(args)
        info = await client.accessibility_info(
            target=AccessibilityPoint(x=args.x, y=args.y),
            options=AccessibilityInfoOptions(
                nested=args.nested,
                keys=args.keys,
                backend=_backend(args),
                format=requested_format,
                profile=args.profile,
                collect_frame_coverage=args.collect_frame_coverage,
            ),
        )
        _warn_if_complete_downgraded(requested_format, info.json)
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
        _add_backend_arg(parser)
        _add_format_arg(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        requested_format = _format(args)
        info = await client.accessibility_info(
            target=AccessibilityMarker(
                value=args.marker,
                match_key=ACCESSIBILITY_KEY_BY_NAME[args.match_key],
                depth=args.depth,
            ),
            options=AccessibilityInfoOptions(
                nested=args.nested,
                backend=_backend(args),
                format=requested_format,
            ),
        )
        _warn_if_complete_downgraded(requested_format, info.json)
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
