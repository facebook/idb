#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class ClearKeychainCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Clear the targets keychain"

    @property
    def name(self) -> str:
        return "clear-keychain"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.clear_keychain()
