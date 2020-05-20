#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from argparse import ArgumentParser, Namespace
from typing import List

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import IdbClient


class RecordVideoCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Record the target's screen to a mp4 video file"

    @property
    def name(self) -> str:
        return "video"

    @property
    def aliases(self) -> List[str]:
        return ["record-video"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("output_file", help="mp4 file to output the video to")
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.record_video(
            stop=signal_handler_event("video"), output_file=args.output_file
        )
