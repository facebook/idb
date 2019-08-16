#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.tar import drain_untar
from idb.grpc.idb_pb2 import Payload, PullRequest, PullResponse
from idb.grpc.stream import generate_bytes
from idb.grpc.types import CompanionClient


async def daemon(client: CompanionClient, request: PullRequest) -> PullResponse:
    destination = request.dst_path
    async with client.stub.pull.open() as stream:
        if not client.is_local:
            # not sending the destination to remote companion
            # so it streams the file back
            request = PullRequest(
                bundle_id=request.bundle_id, src_path=request.src_path, dst_path=None
            )
        await stream.send_message(request)
        await stream.end()
        if client.is_local:
            await stream.recv_message()
        else:
            await drain_untar(generate_bytes(stream), output_path=destination)
        client.logger.info(f"pulled file to {destination}")
    return PullResponse(payload=Payload(file_path=destination))
