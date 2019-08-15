#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.gzip import drain_gzip_decompress
from idb.common.video import generate_video_bytes
from idb.grpc.idb_pb2 import Payload, RecordRequest, RecordResponse
from idb.grpc.stream import Stream
from idb.grpc.types import CompanionClient
from idb.utils.typing import none_throws


Start = RecordRequest.Start
Stop = RecordRequest.Stop


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
        await forward_stream.send_message(RecordRequest(stop=Stop()))
        await forward_stream.end()
        if client.is_local:
            client.logger.info("Responding with file path")
            response = await forward_stream.recv_message()
            await stream.send_message(response)
        else:
            client.logger.info(f"Decompressing gzip to {output_file}")
            await drain_gzip_decompress(
                generate_video_bytes(forward_stream), output_path=output_file
            )
            client.logger.info(f"Finished decompression to {output_file}")
            await stream.send_message(
                RecordResponse(payload=Payload(file_path=output_file))
            )
