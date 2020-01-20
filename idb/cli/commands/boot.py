#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import ManagementCommand
from idb.common.types import IdbManagementClient


class BootCommand(ManagementCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--udid",
            help="Udid of target, can also be set with the IDB_UDID env var",
            default=os.environ.get("IDB_UDID"),
        )
        super().add_parser_arguments(parser)

    @property
    def description(self) -> str:
        return "Boots a simulator (only works on mac)"

    @property
    def name(self) -> str:
        return "boot"

    async def run_with_client(
        self, args: Namespace, client: IdbManagementClient
    ) -> None:
        await client.boot()
