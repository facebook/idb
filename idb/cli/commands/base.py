#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import logging
import os
from abc import ABCMeta, abstractmethod
from argparse import ArgumentParser, Namespace

from idb.client.grpc import GrpcClient
from idb.common import plugin
from idb.common.command import Command
from idb.common.constants import DEFAULT_DAEMON_GRPC_PORT, DEFAULT_DAEMON_HOST
from idb.common.logging import log_call
from idb.common.types import IdbClient


class BaseCommand(Command, metaclass=ABCMeta):
    def __init__(self) -> None:
        super().__init__()
        # Will inherit log levels when the log level is set on the base logger in run()
        self.logger: logging.Logger = logging.getLogger(self.name)

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--log",
            dest="log_level",
            choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
            default="WARNING",
            help="Set the logging level",
        )
        parser.add_argument(
            "--json",
            action="store_true",
            default=False,
            help="Create json structured output",
        )

    async def run(self, args: Namespace) -> None:
        # Set the log level on the base logger
        logging.getLogger().setLevel(args.log_level)
        name = self.__class__.__name__
        self.logger.debug(f"{name} command run with: {args}")
        async with log_call(
            name=name, metadata=plugin.resolve_metadata(logger=self.logger)
        ):
            await self._run_impl(args)

    @abstractmethod
    async def _run_impl(self, args: Namespace) -> None:
        raise Exception("subclass")


class ConnectingCommand(BaseCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        plugin.on_connecting_parser(parser=parser, logger=self.logger)
        parser.add_argument(
            "--daemon-host",
            help="Host the daemon is running on",
            type=str,
            default=DEFAULT_DAEMON_HOST,
        )
        parser.add_argument(
            "--force", help="Kill any implicitly running daemons", action="store_true"
        )
        parser.add_argument(
            "--daemon-grpc-port",
            help="Port the daemon is running it's grpc interface on",
            type=int,
            default=DEFAULT_DAEMON_GRPC_PORT,
        )
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        udid = vars(args).get("udid")
        client = GrpcClient(target_udid=udid, logger=self.logger)
        await self.run_with_client(args=args, client=client)

    @abstractmethod
    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        pass


class TargetCommand(ConnectingCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--udid",
            help="Udid of target, can also be set with the IDB_UDID env var",
            default=os.environ.get("IDB_UDID"),
        )
        super().add_parser_arguments(parser)
