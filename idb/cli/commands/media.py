#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
from argparse import ArgumentParser, Namespace

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import Client


class MediaAddCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Add photos/videos to the target"

    @property
    def name(self) -> str:
        return "add-media"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "file_paths", nargs="+", help="Paths to all media files to add"
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.add_media(file_paths=args.file_paths)


class AudioInjectCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Inject a 16-bit PCM WAV file into the target's microphone input"

    @property
    def name(self) -> str:
        return "inject"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "file",
            help=(
                "Path to the audio file to inject; it must be a 16-bit PCM WAV. An app hears it "
                "only while recording, and only if it was launched after the simulator was first "
                "armed"
            ),
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        await client.inject_audio(audio_file_path=args.file)


class CameraInjectCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Play video files into the cameras of apps the companion launches"

    @property
    def name(self) -> str:
        return "inject"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "back_video",
            help=(
                "Path on the companion's host to the video the back cameras show, and the front "
                "cameras too unless --front is given. An app shows it only if the companion "
                "launched it while the injection runs"
            ),
        )
        parser.add_argument(
            "--front",
            default=None,
            help="Path on the companion's host to the video the front cameras show",
        )
        parser.add_argument(
            "--loop",
            action="store_true",
            help=(
                "Play until interrupted, rather than stopping once a camera has shown the whole "
                "video"
            ),
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        async for processes in client.inject_video(
            back_path=args.back_video,
            front_path=args.front,
            loop=args.loop,
            stop=signal_handler_event("camera injection"),
        ):
            if args.json:
                print(json.dumps({"processes": processes}))
            elif processes:
                print(f"Showing the video in: {', '.join(processes)}")
            else:
                print("No process is showing the video")
