#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class ListTestBundleCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "List the tests inside an installed test bundle"

    @property
    def name(self) -> str:
        return "list-bundle"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "test_bundle_id", help="Bundle id of the test bundle to list", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        tests = await client.list_test_bundle(test_bundle_id=args.test_bundle_id)
        if args.json:
            print(json.dumps(tests))
        else:
            print("\n".join(tests))
