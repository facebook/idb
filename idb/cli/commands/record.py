#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from argparse import Namespace
from typing import Any, List

from idb.cli.commands.base import TargetCommand
from idb.client.client import IdbClient
from idb.common.signal import signal_handler_event


class RecordVideoCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Record the target's screen to a mp4 video file"

    @property
    def name(self) -> str:
        return "video"

    @property
    def aliases(self) -> List[str]:
        return ["record-video"]

    def add_parser_arguments(self, parser: Any) -> None:
        parser.add_argument("output_file", help="mp4 file to output the video to")
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        await client.record_video(
            stop=signal_handler_event("video"), output_file=args.output_file
        )


class RecordGifCommand(TargetCommand):
    @property
    def description(self) -> str:
        return "Record the target's screen to generate a gif."

    @property
    def name(self) -> str:
        return "gif"

    @property
    def aliases(self) -> List[str]:
        return ["record-gif"]

    def add_parser_arguments(self, parser: Any) -> None:
        parser.add_argument("output_file", help="gif file to output the recording to")
        parser.add_argument(
            "--fps", help="fps at which you want to record the gif", type=int, default=1
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        final_gif_path = await client.record_gif(
            stop=signal_handler_event("gif record"),
            output_file=args.output_file,
            fps=args.fps,
        )
        print(final_gif_path)
