#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class DebugServerStartCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Start the Debug Server"

    @property
    def name(self) -> str:
        return "start"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument("bundle_id", help="The bundle id to debug")

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        commands = await client.debugserver_start(bundle_id=args.bundle_id)
        print(*commands, sep="\n")


class DebugServerStopCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Stop the debug server"

    @property
    def name(self) -> str:
        return "stop"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.debugserver_stop()


class DebugServerStatusCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Get the status of the debug server"

    @property
    def name(self) -> str:
        return "status"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        commands = await client.debugserver_status()
        if commands is None:
            print("Not Running")
        else:
            print(*commands, sep="\n")
