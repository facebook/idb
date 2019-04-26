#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class AccessibilityInfoAllCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Describes Accessibility Information for the entire screen"

    @property
    def name(self) -> str:
        return "describe-all"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        info = await client.accessibility_info(point=None)
        print(info.json)


class AccessibilityInfoAtPointCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Describes Accessibility Information at a point on the screen"

    @property
    def name(self) -> str:
        return "describe-point"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("x", help="The x-coordinate", type=int)
        parser.add_argument("y", help="The y-coordinate", type=int)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        info = await client.accessibility_info(point=(args.x, args.y))
        print(info.json)
