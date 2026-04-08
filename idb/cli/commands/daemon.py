#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from argparse import ArgumentParser, Namespace

from idb.cli import BaseCommand


class DaemonCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "This command is deprecated. the idb daemon is not used anymore."

    @property
    def name(self) -> str:
        return "daemon"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        self.logger.error(
            "idb daemon is deprecated and does nothing, please remove usages of it."
        )
