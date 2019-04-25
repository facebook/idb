#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient
from idb.common.format import (
    human_format_installed_test_info,
    json_format_installed_test_info,
)


class ListXctestsCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "List the installed test bundles"

    @property
    def name(self) -> str:
        return "list"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        tests = await client.list_xctests()
        formatter = human_format_installed_test_info
        if args.json:
            formatter = json_format_installed_test_info
        for test in tests:
            print(formatter(test))
