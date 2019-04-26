#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from argparse import ArgumentParser, Namespace


from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient


class InstallXctestCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Install an xctest"

    @property
    def name(self) -> str:
        return "install"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "test_bundle_path", help="Bundle path of the test bundle", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        test_bundle_id = await client.install_xctest(args.test_bundle_path)
        if args.json:
            print(json.dumps({"installedTestBundleId": test_bundle_id}))
        else:
            print(f"Installed: {test_bundle_id}")
