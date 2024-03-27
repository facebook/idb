#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, Compression, FileContainerType


class DsymInstallCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Install dSYM(s)"

    @property
    def name(self) -> str:
        return "install"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--bundle-id",
            help="If specified will install debug symbols inside the app container",
            type=str,
            required=False,
            default=None,
        )
        parser.add_argument("dsym_path", help="Path to dSYM(s) to install", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )

        bundle_type = FileContainerType.APPLICATION if args.bundle_id else None
        async for install_response in client.install_dsym(
            args.dsym_path,
            args.bundle_id,
            compression,
            bundle_type,
        ):
            if install_response.progress != 0.0 and not args.json:
                print("Installed {install_response.progress}%")
            elif args.json:
                print(json.dumps({"dsym": install_response.name}))
            else:
                print(f"Installed: {install_response.name}")
