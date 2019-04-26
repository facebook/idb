#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class ApproveCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Approve permissions for an app"

    @property
    def name(self) -> str:
        return "approve"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("bundle_id", help="App's bundle id", type=str)
        parser.add_argument(
            "permissions",
            nargs="+",
            help="Permissions to approve",
            choices=["photos", "camera", "contacts"],
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.approve(
            bundle_id=args.bundle_id, permissions=set(args.permissions)
        )
