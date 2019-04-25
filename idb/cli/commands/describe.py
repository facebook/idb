#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class DescribeCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Describes the Target"

    @property
    def name(self) -> str:
        return "describe"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        description = await client.describe()
        print(description)
