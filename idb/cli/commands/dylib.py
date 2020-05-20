#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class DylibInstallCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Install an dylib"

    @property
    def name(self) -> str:
        return "install"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("dylib_path", help="Path to the dylib to install", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        async for install_response in client.install_dylib(args.dylib_path):
            if install_response.progress != 0.0 and not args.json:
                print("Installed {install_response.progress}%")
            elif args.json:
                print(
                    json.dumps(
                        {"dylib": install_response.name, "uuid": install_response.uuid}
                    )
                )
            else:
                print(f"Installed: {install_response.name} {install_response.uuid}")
