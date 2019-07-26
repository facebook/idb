#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import TargetCommand
from idb.common.types import IdbClient


class FrameworkInstallCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Install .Framework bundles"

    @property
    def name(self) -> str:
        return "install"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "framework_path", help="Path to .Framework to install", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        artifact = await client.install_framework(args.framework_path)
        if args.json:
            print(json.dumps({"framework": artifact.name, "uuid": artifact.uuid}))
        else:
            print(f"Installed: {artifact.name} {artifact.uuid}")
