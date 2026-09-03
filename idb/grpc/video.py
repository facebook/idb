#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from collections.abc import AsyncIterator

from idb.grpc.idb_pb2 import RecordResponse


async def generate_video_bytes(
    stream: AsyncIterator[RecordResponse],
    applied: list[RecordResponse.Applied] | None = None,
) -> AsyncIterator[bytes]:
    """Yields the recorded bytes. The companion precedes them with the encode options it resolved
    when the request asked for any; that frame carries no video, so it is collected into `applied`
    rather than yielded as an empty chunk."""
    async for response in stream:
        output = response.WhichOneof("output")
        if output == "applied":
            if applied is not None:
                applied.append(response.applied)
        elif output == "payload":
            yield response.payload.data
