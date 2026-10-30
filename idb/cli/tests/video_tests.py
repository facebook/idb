#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import unittest

from idb.cli.commands.video import describe_audio
from idb.common.types import RecordedAudio, RecordedAudioProcess


def _process(
    name: str,
    frames: int,
    dropped_frames: int | None = 0,
    unmixed_frames: int = 0,
) -> RecordedAudioProcess:
    return RecordedAudioProcess(
        pid=41,
        name=name,
        frames=frames,
        dropped_frames=dropped_frames,
        unmixed_frames=unmixed_frames,
        realignments=0,
    )


class DescribeAudioTest(unittest.TestCase):
    def test_says_how_long_from_whom_and_where_it_starts(self) -> None:
        audio = RecordedAudio(
            offset=-0.25,
            frames=72_000,
            sample_rate=48_000,
            wav_file_path="/tmp/screen.wav",
            processes=[_process("Player", 96_000), _process("Silent", 0)],
            failures=[],
        )
        self.assertEqual(
            describe_audio(audio),
            "Audio: 1.50 s from Player (41), starting -0.250 s into the video\n"
            "Uncut audio: /tmp/screen.wav",
        )

    def test_nothing_played_is_said_plainly(self) -> None:
        audio = RecordedAudio(
            offset=0,
            frames=0,
            sample_rate=0,
            wav_file_path=None,
            processes=[],
            failures=[],
        )
        self.assertEqual(describe_audio(audio), "Audio: nothing played")

    def test_what_the_audio_lacks_is_named(self) -> None:
        audio = RecordedAudio(
            offset=0,
            frames=48_000,
            sample_rate=48_000,
            wav_file_path=None,
            processes=[
                _process("Player", 48_000, dropped_frames=12),
                _process("Crashed", 480, dropped_frames=None, unmixed_frames=64),
            ],
            failures=["Recorder: no space left"],
        )
        self.assertEqual(
            describe_audio(audio).splitlines()[1:],
            [
                "Player (41) dropped 12 frames",
                "Crashed (41) exited during the recording",
                "Crashed (41) played 64 frames at another rate, left out",
                "Could not capture Recorder: no space left",
            ],
        )
