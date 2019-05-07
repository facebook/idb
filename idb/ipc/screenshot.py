#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.idb_pb2 import ScreenshotRequest
from idb.grpc.types import CompanionClient


async def client(client: CompanionClient) -> bytes:
    response = await client.stub.screenshot(ScreenshotRequest())
    return response.image_data
