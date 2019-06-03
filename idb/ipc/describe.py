#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.common.types import TargetDescription
from idb.grpc.idb_pb2 import TargetDescriptionRequest, TargetDescriptionResponse
from idb.grpc.types import CompanionClient
from idb.ipc.mapping.target import target_to_py


async def client(client: CompanionClient) -> TargetDescription:
    response = await client.stub.describe(TargetDescriptionRequest())
    return target_to_py(response.target_description)
