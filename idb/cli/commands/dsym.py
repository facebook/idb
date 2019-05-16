#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class DsymInstallCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Install dSYM(s)"

    @property
    def name(self) -> str:
        return "install-dsym"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("dsym_path", help="Path to dSYM(s) to install", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        dsym = await client.install_dsym(args.dsym_path)
        if args.json:
            print(json.dumps({"dsym": dsym}))
        else:
            print(f"Installed: {dsym}")
