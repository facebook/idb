#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.idb_pb2 import InstrumentsRunRequest, InstrumentsRunResponse
from idb.grpc.stream import Stream, join_streams
from idb.grpc.types import CompanionClient


async def daemon(
    client: CompanionClient,
    stream: Stream[InstrumentsRunRequest, InstrumentsRunResponse],
) -> None:
    async with client.stub.instruments_run.open() as out_stream:
        await join_streams(stream, out_stream)
