#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, HIDOrientationType


class RotationCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Read physical orientation, or set it when an orientation is supplied"

    @property
    def name(self) -> str:
        return "rotation"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "orientation",
            nargs="?",
            choices=[orientation.name for orientation in HIDOrientationType],
            help="Physical device orientation; omit to read the current orientation",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        if args.orientation is not None:
            await client.set_orientation(
                orientation=HIDOrientationType[args.orientation]
            )
            return
        orientation = (await client.get_orientation()).name
        print(json.dumps({"orientation": orientation}) if args.json else orientation)
