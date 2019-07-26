#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import TargetCommand
from idb.common.types import IdbClient


class AppInstallCommand(TargetCommand):
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
        artifact = await client.install(args.bundle_path)
        if args.json:
            print(
                json.dumps(
                    {"installedAppBundleId": artifact.name, "uuid": artifact.uuid}
                )
            )
        else:
            print(f"Installed: {artifact.name} {artifact.uuid}")


class AppUninstallCommand(TargetCommand):
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


class AppTerminateCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Terminate a running application"

    @property
    def name(self) -> str:
        return "terminate"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("bundle_id", help="Bundle id of the app to kill", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.terminate(args.bundle_id)
