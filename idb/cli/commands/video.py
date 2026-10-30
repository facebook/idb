#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import json
import sys
from argparse import ArgumentParser, Namespace
from dataclasses import asdict

from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event, signal_handler_generator
from idb.common.types import Client, RecordedAudio, VideoFormat


_FORMAT_CHOICE_MAP: dict[str, VideoFormat] = {
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
    def aliases(self) -> list[str]:
        return ["record-video"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("output_file", help="mp4 file to output the video to")
        parser.add_argument(
            "--fps",
            type=int,
            default=None,
            help="The framerate to record at. Default is 30",
        )
        parser.add_argument(
            "--scale-factor",
            type=float,
            default=None,
            help="Scale the recording (between 0 and 1.0). Default is the source size",
        )
        parser.add_argument(
            "--bitrate",
            type=float,
            default=None,
            help="Target average bits per second. Default lets the encoder choose",
        )
        parser.add_argument(
            "--key-frame-rate",
            type=float,
            default=None,
            help="The maximum seconds between key frames. Default is 4",
        )
        parser.add_argument(
            "--audio",
            action="store_true",
            default=False,
            help="Also record what the simulator's apps play, as an audio track. Only apps "
            "launched through idb are recorded",
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        audio = await client.record_video(
            stop=signal_handler_event("video"),
            output_file=args.output_file,
            fps=args.fps,
            scale_factor=args.scale_factor,
            bitrate=args.bitrate,
            key_frame_rate=args.key_frame_rate,
            audio=args.audio,
        )
        if audio is None:
            return
        print(json.dumps(asdict(audio)) if args.json else describe_audio(audio))


def describe_audio(audio: RecordedAudio) -> str:
    """What a recording's audio holds, in a line per fact."""
    playing = [process for process in audio.processes if process.frames > 0]
    if audio.frames == 0 or audio.sample_rate <= 0:
        lines = ["Audio: nothing played"]
    else:
        sources = ", ".join(f"{process.name} ({process.pid})" for process in playing)
        lines = [
            f"Audio: {audio.frames / audio.sample_rate:.2f} s from {sources or 'no process'}, "
            f"starting {audio.offset:+.3f} s into the video"
        ]
    if audio.wav_file_path:
        lines.append(f"Uncut audio: {audio.wav_file_path}")
    for process in audio.processes:
        name = f"{process.name} ({process.pid})"
        if process.dropped_frames is None:
            lines.append(f"{name} exited during the recording")
        elif process.dropped_frames > 0:
            lines.append(f"{name} dropped {process.dropped_frames} frames")
        if process.unmixed_frames > 0:
            lines.append(
                f"{name} played {process.unmixed_frames} frames at another rate, left out"
            )
    lines += [f"Could not capture {failure}" for failure in audio.failures]
    return "\n".join(lines)


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
