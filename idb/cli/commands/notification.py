#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.types import Client


class SendNotificationCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Open a URL"

    @property
    def name(self) -> str:
        return "send-notification"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("bundle_id", help="Target app", type=str)
        parser.add_argument(
            "json_payload", help="Notification data in json format", type=str
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.send_notification(args.bundle_id, args.json_payload)
