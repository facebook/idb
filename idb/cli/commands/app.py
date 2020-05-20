#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
from argparse import ArgumentParser, Namespace
from typing import Optional

from idb.cli import ClientCommand
from idb.common.format import (
    human_format_installed_app_info,
    json_format_installed_app_info,
)
from idb.common.types import IdbClient, InstalledArtifact
from idb.utils.typing import none_throws


class AppInstallCommand(ClientCommand):
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
        artifact: Optional[InstalledArtifact] = None
        async for info in client.install(args.bundle_path):
            artifact = info
            progress = info.progress
            if progress is None:
                continue
            self.logger.info(f"Progress: {progress}")
        if args.json:
            print(
                json.dumps(
                    {
                        "installedAppBundleId": none_throws(artifact).name,
                        "uuid": none_throws(artifact).uuid,
                    }
                )
            )
        else:
            print(
                f"Installed: {none_throws(artifact).name} {none_throws(artifact).uuid}"
            )


class AppUninstallCommand(ClientCommand):
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


class AppTerminateCommand(ClientCommand):
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


class AppListCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "List the installed apps"

    @property
    def name(self) -> str:
        return "list-apps"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        apps = await client.list_apps()
        formatter = human_format_installed_app_info
        if args.json:
            formatter = json_format_installed_app_info
        for app in apps:
            print(formatter(app))
