#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import AsyncIterator

from idb.grpc.idb_pb2 import RecordResponse


async def generate_video_bytes(
    stream: AsyncIterator[RecordResponse],
) -> AsyncIterator[bytes]:
    async for response in stream:
        data = response.payload.data
        yield data
