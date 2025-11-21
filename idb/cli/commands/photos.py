#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, IdbException, TargetType


class PhotosClearCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Clears all photos"

    @property
    def name(self) -> str:
        return "clear"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        target = await client.describe()
        if target.target_type == TargetType.MAC:
            raise IdbException("photos clear does not work on mac targets")
        await client.photos_clear()
