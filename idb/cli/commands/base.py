#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import logging
import os
from abc import ABCMeta, abstractmethod
from argparse import ArgumentParser, Namespace
from typing import Dict, List, Optional

import idb.common.plugin as plugin
from idb.client.grpc import GrpcClient
from idb.common.constants import DEFAULT_DAEMON_GRPC_PORT, DEFAULT_DAEMON_HOST
from idb.common.logging import log_call
from idb.common.types import IdbClient


class Command(metaclass=ABCMeta):
    @property
    @abstractmethod
    def description(self) -> str:
        raise Exception("subclass")

    @property
    @abstractmethod
    def name(self) -> str:
        raise Exception("subclass")

    @property
    def aliases(self) -> List[str]:
        return []

    @abstractmethod
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        raise Exception("subclass")

    @abstractmethod
    async def run(self, args: Namespace) -> None:
        raise Exception("subclass")

    @property
    def allow_unknown_args(self) -> bool:
        return False


class CompositeCommand(Command, metaclass=ABCMeta):
    parser: Optional[ArgumentParser] = None

    @property
    @abstractmethod
    def subcommands(self) -> List[Command]:
        pass

    @property
    def subcommands_by_name(self) -> Dict[str, Command]:
        def add_unique_cmd(aDict: Dict[str, Command], key: str, value: Command) -> None:
            assert key not in aDict, f'Subcommand by name "{key}" already exists'
            aDict[key] = value

        aDict: Optional[Dict[str, Command]] = getattr(
            self, "_subcommands_by_name", None
        )
        if aDict is None:
            aDict = {}
            # pyre-fixme[16]: `CompositeCommand` has no attribute
            #  `_subcommands_by_name`.
            self._subcommands_by_name = aDict
            for cmd in self.subcommands:
                add_unique_cmd(aDict, cmd.name, cmd)
                for alias in cmd.aliases:
                    add_unique_cmd(aDict, alias, cmd)

        return aDict

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        self.parser = parser
        sub_parsers = parser.add_subparsers(dest=self.name)
        for command in self.subcommands:
            sub_parser = sub_parsers.add_parser(
                command.name, help=command.description, aliases=command.aliases
            )
            command.add_parser_arguments(sub_parser)

    def _get_subcommand_for_args(self, args: Namespace) -> Command:
        subcmd_name = getattr(args, self.name)
        if self.parser and subcmd_name is None:
            self.parser.print_help()
            # This terminates the program with exit code 2
            self.parser.error(f"No subcommand found for {self.name}")
        subcmd = self.subcommands_by_name[subcmd_name]
        assert subcmd is not None, "subcommand %r doesn't exist" % subcmd_name
        return subcmd

    async def run(self, args: Namespace) -> None:
        return await self._get_subcommand_for_args(args).run(args)


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


# pyre-fixme[44]: `ConnectingCommand` non-abstract class with abstract methods
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


class CommandGroup(CompositeCommand):
    def __init__(self, name: str, description: str, commands: List[Command]) -> None:
        self.commands = commands
        self._name = name
        self._description = description

    @property
    def name(self) -> str:
        return self._name

    @property
    def description(self) -> str:
        return self._description

    @property
    def subcommands(self) -> List[Command]:
        return self.commands
