#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import sys
from argparse import ArgumentParser, Namespace
from contextlib import contextmanager
from typing import IO, Iterator

from idb.cli import ClientCommand
from idb.common.types import Client


class ScreenshotCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Take a Screenshot of the Target"

    @property
    def name(self) -> str:
        return "screenshot"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "dest_path",
            help="The destination file path to write to or - (dash) to write to stdout",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        screenshot = await client.screenshot()
        with screenshot_file(args.dest_path) as f:
            f.write(screenshot)


@contextmanager
def screenshot_file(path: str) -> Iterator[IO[bytes]]:
    if path == "-":
        yield sys.stdout.buffer
        return

    with open(path, "wb") as f:
        yield f
