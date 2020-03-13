#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import logging
import os
from abc import ABCMeta, abstractmethod
from argparse import ArgumentParser, Namespace
from typing import AsyncContextManager, Tuple

from idb.client.grpc import (
    IdbClient as IdbClientGrpc,
    IdbManagementClient as IdbManagementClientGrpc,
)
from idb.common import plugin
from idb.common.command import Command
from idb.common.constants import DEFAULT_DAEMON_GRPC_PORT, DEFAULT_DAEMON_HOST
from idb.common.logging import log_call
from idb.common.types import IdbClient, IdbManagementClient
from idb.utils.contextlib import asynccontextmanager


def _parse_companion_info(value: str) -> Tuple[str, int]:
    (host, port) = value.rsplit(":", 1)
    return (host, int(port))


@asynccontextmanager
async def _get_management_client(
    args: Namespace, logger: logging.Logger
) -> AsyncContextManager[IdbManagementClient]:
    yield IdbManagementClientGrpc(logger=logger, companion_path=args.companion_path)


@asynccontextmanager
async def _get_client(
    args: Namespace, logger: logging.Logger
) -> AsyncContextManager[IdbClient]:
    companion = vars(args).get("companion")
    if companion is not None:
        (host, port) = _parse_companion_info(companion)
        async with IdbClientGrpc.build(
            host=host, port=port, is_local=False, logger=logger
        ) as client:
            yield client
    else:
        async with _get_management_client(args=args, logger=logger) as client:
            yield client


def _add_common_client_arguments(
    parser: ArgumentParser, logger: logging.Logger
) -> None:
    plugin.on_connecting_parser(parser=parser, logger=logger)
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


class BaseCommand(Command, metaclass=ABCMeta):
    def __init__(self) -> None:
        super().__init__()
        # Will inherit log levels when the log level is set on the base logger in run()
        self.logger: logging.Logger = logging.getLogger(self.name)

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--log",
            dest="log_level_deprecated",
            choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
            default=None,
            help="Set the logging level. Deprecated: Please place --log before the command name",
        )
        parser.add_argument(
            "--json",
            action="store_true",
            default=False,
            help="Create json structured output",
        )

    async def run(self, args: Namespace) -> None:
        # In order to keep the argparse compatible with old invocations
        # We should use the --log after command if set, otherwise use the pre-command --log
        logging.getLogger().setLevel(args.log_level_deprecated or args.log_level)
        name = self.__class__.__name__
        self.logger.debug(f"{name} command run with: {args}")
        if args.log_level_deprecated is not None:
            self.logger.warning(
                f"Setting --log after the command is deprecated, please place it at the start of the invocation"
            )
        async with log_call(
            name=name, metadata=plugin.resolve_metadata(logger=self.logger)
        ):
            await self._run_impl(args)

    @abstractmethod
    async def _run_impl(self, args: Namespace) -> None:
        raise Exception("subclass")


# A command that vends the IdbClientBase interface.
class CompanionCommand(BaseCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        _add_common_client_arguments(parser=parser, logger=self.logger)
        parser.add_argument(
            "--udid",
            help="Udid of target, can also be set with the IDB_UDID env var",
            default=os.environ.get("IDB_UDID"),
        )
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        async with _get_client(args=args, logger=self.logger) as client:
            await self.run_with_client(args=args, client=client)

    @abstractmethod
    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        pass


# A command that vends the IdbClient interface
class ManagementCommand(BaseCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        _add_common_client_arguments(parser=parser, logger=self.logger)
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        async with _get_management_client(args=args, logger=self.logger) as client:
            await self.run_with_client(args=args, client=client)

    @abstractmethod
    async def run_with_client(
        self, args: Namespace, client: IdbManagementClient
    ) -> None:
        pass
