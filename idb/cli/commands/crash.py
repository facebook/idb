#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import dataclasses
import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client, CrashLogQuery, IdbException


class CrashDeleteException(IdbException):
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
    query = CrashLogQuery(
        before=arguments.before,
        since=arguments.since,
        bundle_id=arguments.bundle_id,
        name=getattr(arguments, "name", None),
    )
    if (
        hasattr(arguments, "all")
        and not arguments.all
        and not any((query.before, query.since, query.bundle_id, query.name))
    ):
        raise CrashDeleteException("Must pass --all if not other arguments specified")
    return query


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

    async def run_with_client(self, args: Namespace, client: Client) -> None:
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

    async def run_with_client(self, args: Namespace, client: Client) -> None:
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

    async def _run_impl(self, args: Namespace) -> None:
        args._crash_delete_query = _build_query(args)
        await super()._run_impl(args)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        query = getattr(args, "_crash_delete_query", None)
        if query is None:
            query = _build_query(args)
        crashes = await client.crash_delete(query=query)
        for crash in crashes:
            print(json.dumps(dataclasses.asdict(crash)))
