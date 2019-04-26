#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace, SUPPRESS
from typing import Union

from idb.cli.commands.base import ConnectingCommand
from idb.client.client import IdbClient
from idb.common.types import Address, IdbException
import idb.common.plugin as plugin


def get_destination(args: Namespace) -> Union[Address, str]:
    target_udid = args.companion if "-" in args.companion else None
    companion_host = args.companion if not target_udid else None
    if target_udid:
        return target_udid
    elif args.port and args.grpc_port and companion_host:
        return Address(host=companion_host, port=args.port, grpc_port=args.grpc_port)
    elif args.port and companion_host:
        return Address(host=companion_host, grpc_port=args.port)
    else:
        raise ConnectCommandException(
            "provide either a UDID or the host and port of the companion"
        )


class ConnectCommandException(Exception):
    pass


class ConnectCommand(ConnectingCommand):
    @property
    def description(self) -> str:
        return "Connect to a companion"

    @property
    def name(self) -> str:
        return "connect"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "companion",
            help="Host the companion is running on. or the UDID of the target",
            type=str,
        )
        parser.add_argument(
            "port",
            help="Port the companion is running on",
            type=int,
            nargs="?",
            default=None,
        )
        parser.add_argument(
            "grpc_port", help=SUPPRESS, type=int, nargs="?", default=None
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        try:
            destination = get_destination(args=args)
            connect_response = await client.connect(
                destination=destination,
                metadata={
                    key: value
                    for (key, value) in plugin.resolve_metadata(self.logger).items()
                    if isinstance(value, str)
                },
            )
            if connect_response:
                if args.json:
                    print(
                        json.dumps(
                            {
                                "udid": connect_response.udid,
                                "is_local": connect_response.is_local,
                            }
                        )
                    )
                else:
                    print(
                        f"udid: {connect_response.udid} is_local: {connect_response.is_local}"
                    )

        except IdbException:
            raise ConnectCommandException(
                f"""Could not connect to {args.companion:}:{args.port}.
            Make sure both host and port are correct and reachable"""
            )
