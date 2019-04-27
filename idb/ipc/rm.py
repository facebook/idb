#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.grpc.types import CompanionClient
from idb.grpc.idb_pb2 import RmRequest, RmResponse


async def client(client: CompanionClient, bundle_id: str, paths: List[str]) -> None:
    await client.stub.rm(RmRequest(bundle_id=bundle_id, paths=paths))


async def daemon(client: CompanionClient, request: RmRequest) -> RmResponse:
    return await client.stub.rm(request)
