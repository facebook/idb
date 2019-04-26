#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class InstallAppCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Install an application"

    @property
    def name(self) -> str:
        return "install"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "bundle_path", help="Path to the .app/.ipa to install", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        bundle_id = await client.install(args.bundle_path)
        if args.json:
            print(json.dumps({"installedAppBundleId": bundle_id}))
        else:
            print(f"Installed: {bundle_id}")


class InstallDylibCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Install an dylib"

    @property
    def name(self) -> str:
        return "install-dylib"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("dylib_path", help="Path to the dylib to install", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        dylib = await client.install_dylib(args.dylib_path)
        if args.json:
            print(json.dumps({"dylib": dylib}))
        else:
            print(f"Installed: {dylib}")
