#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import sys
from argparse import ArgumentParser, Namespace
from typing import Dict, List

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event, signal_handler_generator
from idb.common.types import Client, VideoFormat


_FORMAT_CHOICE_MAP: Dict[str, VideoFormat] = {
    str(format.value.lower()): format for format in VideoFormat
}


class VideoRecordCommand(ClientCommand):
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

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.record_video(
            stop=signal_handler_event("video"), output_file=args.output_file
        )


class VideoStreamCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Stream raw H264 from the target"

    @property
    def name(self) -> str:
        return "video-stream"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--fps",
            required=False,
            default=None,
            type=int,
            help="The framerate of the stream. Default is a dynamic fps",
        )
        parser.add_argument(
            "--format",
            choices=list(_FORMAT_CHOICE_MAP.keys()),
            help="The format of the stream",
            default=VideoFormat.H264.value,
        )
        parser.add_argument(
            "output_file",
            nargs="?",
            default=None,
            help="h264 target file. When omitted, the stream will be written to stdout",
        )
        parser.add_argument(
            "--compression-quality",
            type=float,
            default=0.2,
            help="The compression quality (between 0 and 1.0) for the stream",
        )
        parser.add_argument(
            "--scale-factor",
            type=float,
            default=1,
            help="The scale factor for the source video (between 0 and 1.0) for the stream",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        async for data in signal_handler_generator(
            iterable=client.stream_video(
                output_file=args.output_file,
                fps=args.fps,
                format=_FORMAT_CHOICE_MAP[args.format],
                compression_quality=args.compression_quality,
                scale_factor=args.scale_factor,
            ),
            name="stream",
            logger=self.logger,
        ):
            sys.stdout.buffer.write(data)
