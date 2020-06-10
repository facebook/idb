#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace
from typing import Dict

from idb.cli import ClientCommand
from idb.common.types import IdbClient, Permission


_ARG_TO_ENUM: Dict[str, Permission] = {
    key.lower(): value for (key, value) in Permission.__members__.items()
}


class ApproveCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Approve permissions for an app"

    @property
    def name(self) -> str:
        return "approve"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("bundle_id", help="App's bundle id", type=str)
        parser.add_argument(
            "permissions",
            nargs="+",
            help="Permissions to approve",
            choices=_ARG_TO_ENUM.keys(),
        )
        parser.add_argument(
            "--scheme", help="Url scheme registered by the app to approve", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        if "url" in args.permissions and not args.scheme:
            print("You need to specify --scheme when approving url permissions")
            exit(1)
        await client.approve(
            bundle_id=args.bundle_id,
            permissions={
                _ARG_TO_ENUM[permission_name] for permission_name in args.permissions
            },
            scheme=args.scheme,
        )
