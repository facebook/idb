#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.stream import stream_map
from idb.common.tar import generate_tar
from idb.grpc.idb_pb2 import Payload, PushRequest, PushResponse
from idb.grpc.stream import Stream, drain_to_stream
from idb.grpc.types import CompanionClient


async def daemon(
    client: CompanionClient, stream: Stream[PushResponse, PushRequest]
) -> None:
    async with client.stub.push.open() as companion:
        await companion.send_message(await stream.recv_message())
        if client.is_local:
            generator = stream
        else:
            paths = [request.payload.file_path async for request in stream]
            generator = stream_map(
                generate_tar(paths=paths),
                lambda chunk: PushRequest(payload=Payload(data=chunk)),
            )
        response = await drain_to_stream(
            stream=companion, generator=generator, logger=client.logger
        )
        await stream.send_message(response)
