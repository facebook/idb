#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace

from idb.cli.commands.base import BaseCommand
from idb.client.client import IdbClient


class KillCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "Kill the idb daemon"

    @property
    def name(self) -> str:
        return "kill"

    async def _run_impl(self, args: Namespace) -> None:
        await IdbClient.kill()
