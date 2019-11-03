#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli.commands.base import ConnectingCommand
from idb.common.format import human_format_target_info, json_format_target_info
from idb.common.types import IdbClient


class ListTargetsCommand(ConnectingCommand):
    @property
    def description(self) -> str:
        return "List the connected targets"

    @property
    def name(self) -> str:
        return "list-targets"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        targets = await client.list_targets()
        if len(targets) == 0:
            if not args.json:
                print("No available targets")
            return

        targets = sorted(targets, key=lambda target: target.name)
        formatter = human_format_target_info
        if args.json:
            formatter = json_format_target_info
        for target in targets:
            print(formatter(target))
