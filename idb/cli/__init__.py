#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import json
import logging
import os
from abc import ABCMeta, abstractmethod
from argparse import ArgumentParser, Namespace
from typing import AsyncGenerator, Optional

from idb.common import plugin
from idb.common.command import Command
from idb.common.companion import Companion as LocalCompanion
from idb.common.logging import log_call
from idb.common.types import (
    Address,
    Client,
    ClientManager,
    Companion,
    DomainSocketAddress,
    IdbConnectionException,
    IdbException,
    LoggingMetadata,
    TCPAddress,
)
from idb.grpc.client import Client as GrpcClient
from idb.grpc.management import ClientManager as GrpcClientManager
from idb.utils.contextlib import asynccontextmanager


def _parse_address(value: str) -> Address:
    values = value.rsplit(":", 1)
    if len(values) == 1:
        return DomainSocketAddress(path=value)
    (host, port) = values
    return TCPAddress(host=host, port=int(port))


def _get_management_client(logger: logging.Logger, args: Namespace) -> ClientManager:
    return GrpcClientManager(
        companion_path=args.companion_path,
        logger=logger,
        prune_dead_companion=args.prune_dead_companion,
    )


@asynccontextmanager
async def _get_client(
    args: Namespace, logger: logging.Logger
) -> AsyncGenerator[GrpcClient, None]:
    companion = vars(args).get("companion")
    if companion is not None:
        async with GrpcClient.build(
            address=_parse_address(companion),
            logger=logger,
            use_tls=args.companion_tls,
        ) as client:
            yield client
    else:
        async with GrpcClientManager(
            logger=logger, companion_path=args.companion_path
        ).from_udid(udid=vars(args).get("udid")) as client:
            yield client


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
                "Setting --log after the command is deprecated, please place it at the start of the invocation"
            )
        metadata: LoggingMetadata = plugin.resolve_metadata(logger=self.logger)
        metadata["arguments"] = json.dumps(args.__dict__, default=lambda v: str(v))
        async with log_call(
            name=name,
            metadata=metadata,
        ):
            await self._run_impl(args)

    @abstractmethod
    async def _run_impl(self, args: Namespace) -> None:
        raise Exception("subclass")


# A command that vends the IdbClient interface.
class ClientCommand(BaseCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--udid",
            help="Udid of target, can also be set with the IDB_UDID env var",
            default=os.environ.get("IDB_UDID"),
        )
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        address: Optional[Address] = None
        try:
            async with _get_client(args=args, logger=self.logger) as client:
                address = client.address
                await self.run_with_client(args=args, client=client)
        except IdbConnectionException as ex:
            if not args.prune_dead_companion:
                raise ex
            if address is None:
                raise ex
            try:
                await _get_management_client(logger=self.logger, args=args).disconnect(
                    destination=address
                )
            finally:
                raise ex

    @abstractmethod
    async def run_with_client(self, args: Namespace, client: Client) -> None:
        pass


# A command that vends the ClientManagerface
class ManagementCommand(BaseCommand):
    async def _run_impl(self, args: Namespace) -> None:
        await self.run_with_manager(
            args=args, manager=_get_management_client(logger=self.logger, args=args)
        )

    @abstractmethod
    async def run_with_manager(self, args: Namespace, manager: ClientManager) -> None:
        pass


# A command that vends the Companion interface
class CompanionCommand(BaseCommand):
    async def _run_impl(self, args: Namespace) -> None:
        companion_path = args.companion_path
        if companion_path is None:
            raise IdbException(
                "Companion interactions do not work on non-macOS platforms"
            )
        await self.run_with_companion(
            args=args,
            companion=LocalCompanion(
                companion_path=companion_path, device_set_path=None, logger=self.logger
            ),
        )

    @abstractmethod
    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        pass
