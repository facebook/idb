#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.idb_pb2 import LaunchRequest, LaunchResponse
from idb.grpc.stream import Stream, join_streams
from idb.grpc.types import CompanionClient


async def daemon(
    client: CompanionClient, stream: Stream[LaunchRequest, LaunchResponse]
) -> None:
    async with client.stub.launch.open() as out_stream:
        await join_streams(stream, out_stream)
