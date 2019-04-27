#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.grpc.types import CompanionClient
from idb.grpc.stream import Stream, drain_to_stream
from idb.common.stream import stream_map
from idb.common.tar import generate_tar
from idb.grpc.idb_pb2 import AddMediaRequest, AddMediaResponse, Payload


async def client(client: CompanionClient, file_paths: List[str]) -> None:
    async with client.stub.add_media.open() as stream:
        for file_path in file_paths:
            await stream.send_message(
                AddMediaRequest(payload=Payload(file_path=file_path))
            )
        await stream.end()
        await stream.recv_message()


async def daemon(
    client: CompanionClient, stream: Stream[AddMediaResponse, AddMediaRequest]
) -> None:
    async with client.stub.add_media.open() as companion:
        if client.is_local:
            generator = stream
        else:
            paths = [request.payload.file_path async for request in stream]
            generator = stream_map(
                generate_tar(paths=paths, place_in_subfolders=True),
                lambda chunk: AddMediaRequest(payload=Payload(data=chunk)),
            )
        response = await drain_to_stream(
            stream=companion, generator=generator, logger=client.logger
        )
        await stream.send_message(response)
