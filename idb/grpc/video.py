#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from collections.abc import AsyncIterator

from idb.common.types import RecordedAudio, RecordedAudioProcess
from idb.grpc.idb_pb2 import RecordResponse


async def generate_video_bytes(
    stream: AsyncIterator[RecordResponse],
    applied: list[RecordResponse.Applied] | None = None,
    audio: list[RecordResponse.Audio] | None = None,
) -> AsyncIterator[bytes]:
    """Yields the recorded bytes. The companion precedes them with the encode options it resolved
    when the request asked for any, and with a description of the audio when it recorded some;
    those frames carry no video, so they are collected into `applied` and `audio` rather than
    yielded as empty chunks."""
    async for response in stream:
        output = response.WhichOneof("output")
        if output == "applied":
            if applied is not None:
                applied.append(response.applied)
        elif output == "audio":
            if audio is not None:
                audio.append(response.audio)
        elif output == "payload":
            yield response.payload.data


def recorded_audio_from_grpc(audio: RecordResponse.Audio) -> RecordedAudio:
    return RecordedAudio(
        offset=audio.offset,
        frames=audio.frames,
        sample_rate=audio.sample_rate,
        wav_file_path=audio.wav_file_path or None,
        processes=[
            RecordedAudioProcess(
                pid=process.pid,
                name=process.name,
                frames=process.frames,
                dropped_frames=(
                    process.dropped_frames if process.dropped_frames >= 0 else None
                ),
                unmixed_frames=process.unmixed_frames,
                realignments=process.realignments,
            )
            for process in audio.processes
        ],
        failures=list(audio.failures),
    )
