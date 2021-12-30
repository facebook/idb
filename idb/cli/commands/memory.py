#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import Namespace

from idb.cli import ClientCommand
from idb.common.types import Client


class SimulateMemoryWarningCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Simulate a memory warning"

    @property
    def name(self) -> str:
        return "simulate-memory-warning"

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.simulate_memory_warning()
