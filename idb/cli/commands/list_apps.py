#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import Namespace

from idb.cli.commands.base import TargetCommand
from idb.common.format import (
    human_format_installed_app_info,
    json_format_installed_app_info,
)
from idb.common.types import IdbClient


class ListAppsCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "List the installed apps"

    @property
    def name(self) -> str:
        return "list-apps"

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        apps = await client.list_apps()
        formatter = human_format_installed_app_info
        if args.json:
            formatter = json_format_installed_app_info
        for app in apps:
            print(formatter(app))
