#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import HIDButtonType, IdbClient


class TapCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Tap On the Screen"

    @property
    def name(self) -> str:
        return "tap"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("x", help="The x-coordinate", type=int)
        parser.add_argument("y", help="The y-coordinate", type=int)
        parser.add_argument("--duration", help="Press duration", type=float)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.tap(x=args.x, y=args.y, duration=args.duration)


class ButtonCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "A single press of a button"

    @property
    def name(self) -> str:
        return "button"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "button",
            help="The button name",
            choices=[button.name for button in HIDButtonType],
            type=str,
        )
        parser.add_argument("--duration", help="Press duration", type=float)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.button(
            button_type=HIDButtonType[args.button], duration=args.duration
        )


class KeyCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "A short press of a keycode"

    @property
    def name(self) -> str:
        return "key"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("key", help="The key code", type=int)
        parser.add_argument("--duration", help="Press duration", type=float)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.key(keycode=args.key, duration=args.duration)


class KeySequenceCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "A sequence of short presses of a keycode"

    @property
    def name(self) -> str:
        return "key-sequence"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "key_sequence",
            help="list of space separated key codes string (i.e. 1 2 3))",
            nargs="*",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.key_sequence(key_sequence=list(map(int, args.key_sequence)))


class TextCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Input text"

    @property
    def name(self) -> str:
        return "text"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("text", help="Text to input", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.text(text=args.text)


class SwipeCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Swipe from one point to another point"

    @property
    def name(self) -> str:
        return "swipe"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "x_start", help="The x-coordinate of the swipe start point", type=int
        )
        parser.add_argument(
            "y_start", help="The y-coordinate of the swipe start point", type=int
        )
        parser.add_argument(
            "x_end", help="The x-coordinate of the swipe end point", type=int
        )
        parser.add_argument(
            "y_end", help="The y-coordinate of the swipe end point", type=int
        )

        parser.add_argument("--duration", help="Swipe duration", type=float)

        parser.add_argument(
            "--delta",
            dest="delta",
            help="delta in pixels between every touch point on the line "
            "between start and end points",
            type=int,
            required=False,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.swipe(
            p_start=(args.x_start, args.y_start),
            p_end=(args.x_end, args.y_end),
            duration=args.duration,
            delta=args.delta,
        )
