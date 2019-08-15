#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import AsyncIterator

from idb.grpc.idb_pb2 import RecordResponse


async def generate_video_bytes(
    stream: AsyncIterator[RecordResponse],
) -> AsyncIterator[bytes]:
    async for response in stream:
        data = response.payload.data
        yield data
