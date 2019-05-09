#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.idb_pb2 import MkdirRequest
from idb.grpc.types import CompanionClient


async def client(client: CompanionClient, bundle_id: str, path: str) -> None:
    await client.stub.mkdir(MkdirRequest(bundle_id=bundle_id, path=path))
