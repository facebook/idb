#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import ArgumentParser, Namespace
from typing import Union

from idb.cli.commands.base import ConnectingCommand
from idb.client.client import IdbClient
from idb.common.types import Address, IdbException


def get_destination(args: Namespace) -> Union[Address, str]:
    target_udid = args.companion if "-" in args.companion else None
    companion_host = args.companion if not target_udid else None
    if target_udid:
        return target_udid
    elif args.port and companion_host:
        return Address(host=companion_host, grpc_port=args.port)
    else:
        raise DisconnectCommandException(
            "provide either a UDID or the host and port of the companion"
        )


class DisconnectCommandException(Exception):
    pass


class DisconnectCommand(ConnectingCommand):
    @property
    def description(self) -> str:
        return "Disconnect a companion"

    @property
    def name(self) -> str:
        return "disconnect"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "companion",
            help="Host the companion is running on or the udid of the target",
            type=str,
        )
        parser.add_argument(
            "port",
            help="Port the companion is running on",
            type=int,
            nargs="?",
            default=None,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        try:
            destination = get_destination(args=args)
            await client.disconnect(destination=destination)
        except IdbException:
            raise DisconnectCommandException(
                f"Could not disconnect from {args.companion:}:{args.port}"
            )
