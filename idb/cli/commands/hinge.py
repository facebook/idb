#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
from argparse import ArgumentParser, ArgumentTypeError, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, HIDHinge


def _hinge_angle(value: str) -> float:
    try:
        return HIDHinge(angle=float(value)).angle
    except ValueError as error:
        raise ArgumentTypeError(str(error)) from error


class HingeCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Read the simulator hinge angle, or set it when an angle is supplied"

    @property
    def name(self) -> str:
        return "hinge"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "angle",
            nargs="?",
            type=_hinge_angle,
            help="Degrees from 0 (closed) to 180 (flat); omit to read the current angle",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        if args.angle is not None:
            await client.set_hinge_angle(angle=args.angle)
            return
        angle = await client.get_hinge_angle()
        print(json.dumps({"angle": angle}) if args.json else angle)
