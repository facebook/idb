#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


import asyncio
from typing import AsyncIterator

from idb.grpc.types import CompanionClient
from idb.grpc.stream import Stream
from idb.common.gzip import drain_gzip_decompress
from idb.grpc.idb_pb2 import Payload, RecordRequest, RecordResponse
from idb.utils.typing import none_throws


Start = RecordRequest.Start
Stop = RecordRequest.Stop


async def _generate_bytes(
    stream: AsyncIterator[RecordResponse],
) -> AsyncIterator[bytes]:
    async for response in stream:
        data = response.payload.data
        yield data


async def daemon(
    client: CompanionClient, stream: Stream[RecordResponse, RecordRequest]
) -> None:
    client.logger.info(f"Starting connection to backend")
    request = await stream.recv_message()
    output_file = none_throws(request).start.file_path
    async with client.stub.record.open() as forward_stream:
        if client.is_local:
            client.logger.info(f"Starting video recording to local file {output_file}")
            await forward_stream.send_message(
                RecordRequest(start=Start(file_path=output_file))
            )
        else:
            client.logger.info(f"Starting video recording with response data")
            await forward_stream.send_message(
                RecordRequest(start=Start(file_path=None))
            )
        client.logger.info("Request sent")
        await stream.recv_message()
        client.logger.info("Stopping video recording")
        await forward_stream.send_message(RecordRequest(stop=Stop()), end=True)
        if client.is_local:
            client.logger.info("Responding with file path")
            response = await forward_stream.recv_message()
            await stream.send_message(response)
        else:
            client.logger.info(f"Decompressing gzip to {output_file}")
            await drain_gzip_decompress(
                _generate_bytes(forward_stream), output_path=output_file
            )
            client.logger.info(f"Finished decompression to {output_file}")
            await stream.send_message(
                RecordResponse(payload=Payload(file_path=output_file))
            )


async def record_video(
    client: CompanionClient, stop: asyncio.Event, output_file: str
) -> None:
    client.logger.info(f"Starting connection to backend")
    async with client.stub.record.open() as stream:
        client.logger.info("Starting video recording")
        await stream.send_message(RecordRequest(start=Start(file_path=output_file)))
        client.logger.info("Request sent")
        await stop.wait()
        client.logger.info("Stopping video recording")
        await stream.send_message(RecordRequest(stop=Stop()), end=True)
        await stream.recv_message()


CLIENT_PROPERTIES = [record_video]  # pyre-ignore
