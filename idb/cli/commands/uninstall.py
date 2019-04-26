#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class UninstallCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Uninstall an application"

    @property
    def name(self) -> str:
        return "uninstall"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "bundle_id", help="Bundle ID of application to uninstall", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.uninstall(bundle_id=args.bundle_id)
