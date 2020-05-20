#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import Namespace

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class KeychainClearCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Clear the targets keychain"

    @property
    def name(self) -> str:
        return "clear-keychain"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.clear_keychain()
