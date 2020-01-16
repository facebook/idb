#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from abc import ABCMeta, abstractmethod
from argparse import ArgumentParser, Namespace
from typing import Dict, List, Optional


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
    def __init__(self) -> None:
        self.parser: Optional[ArgumentParser] = None
        self._subcommands_by_name: Dict[str, Command] = {}

    @property
    @abstractmethod
    def subcommands(self) -> List[Command]:
        pass

    @property
    def subcommands_by_name(self) -> Dict[str, Command]:
        def add_unique_cmd(key: str, value: Command) -> None:
            assert (
                key not in self._subcommands_by_name
            ), f'Subcommand by name "{key}" already exists'
            self._subcommands_by_name[key] = value

        if len(self._subcommands_by_name) == 0:
            for cmd in self.subcommands:
                add_unique_cmd(cmd.name, cmd)
                for alias in cmd.aliases:
                    add_unique_cmd(alias, cmd)

        return self._subcommands_by_name

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
        parser = self.parser
        if parser is not None and subcmd_name is None:
            parser.print_help()
            parser.error(f"No subcommand found for {self.name}")
            raise Exception("Should not reach here")
        subcmd = self.subcommands_by_name[subcmd_name]
        assert subcmd is not None, "subcommand %r doesn't exist" % subcmd_name
        return subcmd

    async def run(self, args: Namespace) -> None:
        return await self._get_subcommand_for_args(args).run(args)


class CommandGroup(CompositeCommand):
    def __init__(self, name: str, description: str, commands: List[Command]) -> None:
        super().__init__()
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
