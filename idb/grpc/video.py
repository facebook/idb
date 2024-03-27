#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from typing import AsyncIterator

from idb.grpc.idb_pb2 import RecordResponse


async def generate_video_bytes(
    stream: AsyncIterator[RecordResponse],
) -> AsyncIterator[bytes]:
    async for response in stream:
        data = response.payload.data
        yield data
