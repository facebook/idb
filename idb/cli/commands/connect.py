#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
from argparse import SUPPRESS, ArgumentParser, Namespace
from typing import Union

import idb.common.plugin as plugin
from idb.cli.commands.base import ConnectingCommand
from idb.common.types import Address, IdbClient, IdbException
from idb.common.udid import is_udid


def get_destination(args: Namespace) -> Union[Address, str]:
    if is_udid(args.companion):
        return args.companion
    elif args.port and args.companion:
        return Address(host=args.companion, port=args.port)
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
        # not used and suppressed. remove after the removal of thrift is deployed everywhere
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
