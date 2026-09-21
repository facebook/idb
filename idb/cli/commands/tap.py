#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from argparse import ArgumentParser, Namespace
from enum import Enum, unique

from idb.cli import ClientCommand
from idb.cli.commands.accessibility import action_backend
from idb.common.types import (
    ACCESSIBILITY_BACKEND_BY_NAME,
    ACCESSIBILITY_KEY_BY_NAME as _SEARCHABLE_KEY_NAMES,
    AccessibilityMarker,
    AccessibilityPoint,
    AccessibilityTarget,
    Client,
    IdbException,
)


def _is_int(value: str) -> bool:
    try:
        int(value)
        return True
    except ValueError:
        return False


@unique
class TapDispatch(Enum):
    COORDINATE_HID = "coordinate_hid"
    EXPECTED_VALUE = "expected_value"
    AX_POINT = "ax_point"
    MARKER = "marker"
    INVALID = "invalid"


class TapCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Tap On the Screen by coordinates or accessibility marker"

    @property
    def name(self) -> str:
        return "tap"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "target",
            nargs="+",
            help="Either 'x y' coordinates, or a single accessibility marker "
            "string (always an accessibility press)",
        )
        parser.add_argument("--duration", help="Press duration", type=float)
        parser.add_argument(
            "--api",
            choices=["hid", *ACCESSIBILITY_BACKEND_BY_NAME],
            default=None,
            help="How the tap is delivered: hid is a coordinate touch; ax and "
            "axbridge are accessibility presses, served by the named backend. "
            "A marker is always a press, served by axbridge unless this says "
            "otherwise, because it is the only backend that can see across a "
            "process boundary such as web content in Safari. A coordinate with "
            "no choice here is a hid touch, as before.",
        )
        parser.add_argument(
            "--match-key",
            choices=list(_SEARCHABLE_KEY_NAMES),
            default="AXLabel",
            help="Accessibility key to match the marker against",
        )
        parser.add_argument(
            "--depth",
            type=int,
            default=10,
            help="Maximum tree depth to search for a marker",
        )
        parser.add_argument(
            "--expected-value",
            help="Value the element must have (for --expected-key) before tapping",
        )
        parser.add_argument(
            "--expected-key",
            choices=list(_SEARCHABLE_KEY_NAMES),
            default="AXLabel",
            help="Accessibility key to check --expected-value against",
        )
        parser.add_argument(
            "--ignore-case",
            action="store_true",
            default=False,
            help="Compare the marker case-insensitively",
        )
        super().add_parser_arguments(parser)

    def is_coordinate_hid_tap(self, args: Namespace) -> bool:
        target = args.target
        return (
            len(target) == 2
            and _is_int(target[0])
            and _is_int(target[1])
            # Every --api value but hid names an accessibility backend, so only
            # hid or no choice at all leaves a coordinate on the HID path.
            and args.api not in ACCESSIBILITY_BACKEND_BY_NAME
            and args.expected_value is None
        )

    def tap_dispatch(self, args: Namespace) -> TapDispatch:
        target = args.target
        if self.is_coordinate_hid_tap(args):
            return TapDispatch.COORDINATE_HID
        if args.expected_value is not None:
            return TapDispatch.EXPECTED_VALUE
        if len(target) == 2 and _is_int(target[0]) and _is_int(target[1]):
            return TapDispatch.AX_POINT
        if len(target) == 1:
            return TapDispatch.MARKER
        return TapDispatch.INVALID

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        target = args.target
        is_point = len(target) == 2 and _is_int(target[0]) and _is_int(target[1])
        is_marker = not is_point and len(target) == 1

        # A marker is always resolved via the accessibility API; `--api hid` only
        # applies to a coordinate, so reject the contradiction outright.
        if is_marker and args.api == "hid":
            raise IdbException(
                "a marker tap is always an accessibility press; drop --api hid, "
                "name an accessibility backend, or pass 'x y' coordinates"
            )

        if self.is_coordinate_hid_tap(args):
            await client.tap(x=int(target[0]), y=int(target[1]), duration=args.duration)
            return

        if args.duration is not None:
            raise IdbException(
                "--duration is only valid for coordinate HID taps (not --api ax "
                "or marker taps)"
            )
        if is_point:
            ax_target: AccessibilityTarget = AccessibilityPoint(
                x=int(target[0]), y=int(target[1])
            )
        elif is_marker:
            ax_target = AccessibilityMarker(
                value=target[0],
                match_key=_SEARCHABLE_KEY_NAMES[args.match_key],
                depth=args.depth,
            )
        else:
            raise IdbException(
                "ui tap expects 'x y' coordinates or a single marker string"
            )
        await client.accessibility_tap(
            target=ax_target,
            expected_value=args.expected_value,
            expected_key=_SEARCHABLE_KEY_NAMES[args.expected_key],
            ignore_case=args.ignore_case,
            backend=action_backend(args),
        )
