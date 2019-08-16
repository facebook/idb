#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.idb_pb2 import HIDEvent as GrpcHIDEvent, HIDResponse
from idb.grpc.stream import Stream, drain_to_stream
from idb.grpc.types import CompanionClient


async def daemon(
    client: CompanionClient, stream: Stream[GrpcHIDEvent, HIDResponse]
) -> None:
    async with client.stub.hid.open() as companion:
        response = await drain_to_stream(
            stream=companion, generator=stream, logger=client.logger
        )
        await stream.send_message(response)
