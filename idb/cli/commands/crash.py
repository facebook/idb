#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import dataclasses
import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import CrashLogQuery, IdbClient


class CrashDeleteException(Exception):
    pass


def _add_query_arguments(parser: ArgumentParser) -> None:
    parser.add_argument(
        "--before", help="Match based older than the provided unix timestamp", type=int
    )
    parser.add_argument(
        "--since",
        help="Match based on being newer than the provided unix timestamp",
        type=int,
    )
    parser.add_argument(
        "--bundle-id",
        help="Filter based on the bundle id of the crashed process",
        type=str,
    )


def _build_query(arguments: Namespace) -> CrashLogQuery:
    if (
        hasattr(arguments, "all")
        and not arguments.all
        and hasattr(arguments, "name")
        and not arguments.name
        and arguments.before is None
        and arguments.since is None
        and arguments.bundle_id is None
    ):
        raise CrashDeleteException("Must pass --all if not other arguments specified")

    return CrashLogQuery(
        before=arguments.before,
        since=arguments.since,
        bundle_id=arguments.bundle_id,
        name=getattr(arguments, "name", None),
    )


class CrashListCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "List the available crashes"

    @property
    def name(self) -> str:
        return "list"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        _add_query_arguments(parser=parser)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        crashes = await client.crash_list(query=_build_query(args))
        for crash in crashes:
            print(json.dumps(dataclasses.asdict(crash)))


class CrashShowCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Fetch a crash log"

    @property
    def name(self) -> str:
        return "show"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("name", help="The unique name of the crash")
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        crash = await client.crash_show(name=args.name)
        print(crash.contents)


class CrashDeleteCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Delete a crash log"

    @property
    def name(self) -> str:
        return "delete"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "name", nargs="?", default=None, help="The unique name of the crash"
        )
        _add_query_arguments(parser=parser)
        parser.add_argument("--all", help="Delete all crash logs", action="store_true")
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        crashes = await client.crash_delete(query=_build_query(args))
        for crash in crashes:
            print(json.dumps(dataclasses.asdict(crash)))
