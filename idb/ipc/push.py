#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.grpc.types import CompanionClient
from idb.grpc.stream import Stream, drain_to_stream
from idb.common.stream import stream_map
from idb.common.tar import generate_tar
from idb.grpc.idb_pb2 import Payload, PushRequest, PushResponse


Inner = PushRequest.Inner


async def client(
    client: CompanionClient, src_paths: List[str], bundle_id: str, dest_path: str
) -> None:
    async with client.stub.push.open() as stream:
        await stream.send_message(
            PushRequest(inner=Inner(bundle_id=bundle_id, dst_path=dest_path))
        )
        for src_path in src_paths:
            await stream.send_message(PushRequest(payload=Payload(file_path=src_path)))
        await stream.end()
        await stream.recv_message()


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
