#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import Namespace

from idb.cli import ManagementCommand
from idb.common.types import IdbManagementClient


class KillCommand(ManagementCommand):
    @property
    def description(self) -> str:
        return "Kill the idb daemon"

    @property
    def name(self) -> str:
        return "kill"

    async def run_with_client(
        self, args: Namespace, client: IdbManagementClient
    ) -> None:
        await client.kill()
