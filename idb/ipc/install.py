#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.install import generate_binary_chunks
from idb.grpc.idb_pb2 import InstallRequest, InstallResponse
from idb.grpc.stream import Stream, drain_to_stream
from idb.grpc.types import CompanionClient
from idb.utils.typing import none_throws


async def daemon(
    client: CompanionClient, stream: Stream[InstallResponse, InstallRequest]
) -> None:
    destination_message = none_throws(await stream.recv_message())
    payload_message = none_throws(await stream.recv_message())
    file_path = payload_message.payload.file_path
    url = payload_message.payload.url
    data = payload_message.payload.data
    destination = destination_message.destination
    async with client.stub.install.open() as forward_stream:
        await forward_stream.send_message(destination_message)
        if client.is_local or len(url):
            await forward_stream.send_message(payload_message)
            await forward_stream.end()
            response = none_throws(await forward_stream.recv_message())
        elif file_path:
            response = await drain_to_stream(
                stream=forward_stream,
                generator=generate_binary_chunks(
                    path=file_path, destination=destination, logger=client.logger
                ),
                logger=client.logger,
            )
        elif data:
            await forward_stream.send_message(payload_message)
            response = await drain_to_stream(
                stream=forward_stream, generator=stream, logger=client.logger
            )
        else:
            raise Exception(f"Unrecognised payload message")
        await stream.send_message(response)
