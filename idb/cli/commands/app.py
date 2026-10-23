#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
import sys
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand, print_upload_progress
from idb.common.format import (
    human_format_installed_app_info,
    json_format_installed_app_info,
)
from idb.common.types import (
    Client,
    Compression,
    IdbException,
    InstalledArtifact,
    TCPAddress,
)
from idb.utils.typing import none_throws


def parse_connect_to(value: str) -> TCPAddress:
    """HOST:PORT, with an IPv6 address in brackets, as curl writes a connect-to target."""
    host, separator, port = value.rpartition(":")
    if host.startswith("[") and host.endswith("]"):
        host = host[1:-1]
    elif ":" in host:
        raise IdbException(f"--connect-to: put an IPv6 address in brackets: {value}")
    if (
        not separator
        or not host
        or "[" in host
        or "]" in host
        or not (port.isascii() and port.isdigit())
        or not 0 < int(port) < 65536
    ):
        raise IdbException(
            f"--connect-to: expected HOST:PORT with a port from 1 to 65535: {value}"
        )
    return TCPAddress(host=host, port=int(port))


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
            "--connect-to",
            help="For a URL: open the download's connection to HOST:PORT instead of the address the URL's host resolves to, as curl's --connect-to does. The URL's host is still the name TLS verifies and the HTTP Host asked for. Put an IPv6 address in brackets: [2001:db8::1]:443.",
            type=str,
            default=None,
            required=False,
            metavar="HOST:PORT",
        )
        parser.add_argument(
            "bundle_path",
            help="Path to the .app/.ipa to install. Note that .app bundles will usually be faster to install than .ipa files.",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        artifact: InstalledArtifact | None = None
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )
        async for info in client.install(
            bundle=sys.stdin.buffer if args.bundle_path == "-" else args.bundle_path,
            make_debuggable=args.make_debuggable,
            compression=compression,
            override_modification_time=args.override_mtime,
            connect_to=(
                parse_connect_to(args.connect_to)
                if args.connect_to is not None
                else None
            ),
            on_upload_progress=print_upload_progress,
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
