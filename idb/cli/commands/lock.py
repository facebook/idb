#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, IdbException, LockState, TargetType


def _print_lock_state(state: LockState, as_json: bool) -> None:
    if as_json:
        print(json.dumps({"locked": state.locked}))
    else:
        print("locked" if state.locked else "unlocked")


async def _require_simulator(client: Client, command: str) -> None:
    target = await client.describe()
    if target.target_type != TargetType.SIMULATOR:
        raise IdbException(f"ui {command} only works on simulator targets")


class LockCommand(ClientCommand):
    @property
    def description(self) -> str:
        return (
            "Lock the simulator through SpringBoard; a locked simulator stays "
            "locked. With --status, print the lock state and change nothing"
        )

    @property
    def name(self) -> str:
        return "lock"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--status",
            action="store_true",
            help="Print whether the simulator is locked, as SpringBoard reports it, without locking it",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await _require_simulator(client, self.name)
        state = await client.lock_state() if args.status else await client.lock()
        _print_lock_state(state, args.json)


class UnlockCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Unlock the simulator through SpringBoard; an unlocked simulator stays unlocked. A simulator with a passcode is an error"

    @property
    def name(self) -> str:
        return "unlock"

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await _require_simulator(client, self.name)
        _print_lock_state(await client.unlock(), args.json)
