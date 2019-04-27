#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.types import CompanionClient
from idb.grpc.idb_pb2 import TargetDescriptionRequest, TargetDescriptionResponse


async def client(client: CompanionClient) -> TargetDescriptionResponse:
    return await client.stub.describe(TargetDescriptionRequest())
