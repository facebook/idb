#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class FocusCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Brings the simulator window to front"

    @property
    def name(self) -> str:
        return "focus"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.focus()
