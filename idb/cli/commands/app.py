#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import json
from argparse import ArgumentParser, Namespace
from typing import Optional

from idb.cli import ClientCommand
from idb.common.format import (
    human_format_installed_app_info,
    json_format_installed_app_info,
)
from idb.common.types import Client, Compression, InstalledArtifact
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
            "--make-debuggable",
            help="If set, will persist the application bundle alongside the iOS Target, this is needed for debugserver commands to function",
            action="store_true",
            default=None,
            required=False,
        )
        parser.add_argument(
            "--override-mtime",
            help="If set, idb will disregard the mtime of files contained in an .ipa file. Current timestamp will be used as modification time. Use this flag to ensure app updates work properly when your build system normalises the timestamps of contents of archives.",
            action="store_true",
            default=None,
            required=False,
        )
        parser.add_argument(
            "bundle_path",
            help="Path to the .app/.ipa to install. Note that .app bundles will usually be faster to install than .ipa files.",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        artifact: Optional[InstalledArtifact] = None
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )
        async for info in client.install(
            bundle=args.bundle_path,
            make_debuggable=args.make_debuggable,
            compression=compression,
            override_modification_time=args.override_mtime,
        ):
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

    async def run_with_client(self, args: Namespace, client: Client) -> None:
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

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.terminate(args.bundle_id)


class AppListCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "List the installed apps"

    @property
    def name(self) -> str:
        return "list-apps"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        group = parser.add_mutually_exclusive_group()
        group.add_argument(
            "--fetch-process-state",
            action="store_true",
            default=True,
            dest="fetch_process_state",
            help="Fetches App Process State",
            required=False,
        )
        group.add_argument(
            "--no-fetch-process-state",
            action="store_false",
            dest="fetch_process_state",
            help="Disables App Process State fetching",
            required=False,
        )

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        apps = await client.list_apps(fetch_process_state=args.fetch_process_state)
        formatter = human_format_installed_app_info
        if args.json:
            formatter = json_format_installed_app_info
        for app in apps:
            print(formatter(app))
