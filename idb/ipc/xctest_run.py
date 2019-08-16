#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.idb_pb2 import XctestRunRequest, XctestRunResponse
from idb.grpc.stream import Stream
from idb.grpc.types import CompanionClient


async def daemon(
    client: CompanionClient, stream: Stream[XctestRunRequest, XctestRunResponse]
) -> None:
    async with client.stub.xctest_run.open() as out_stream:
        async for message in stream:
            await out_stream.send_message(message)
        await out_stream.end()
        async for response in out_stream:
            await stream.send_message(response)
