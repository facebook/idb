#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.idb_pb2 import OpenUrlRequest
from idb.grpc.types import CompanionClient


async def client(client: CompanionClient, url: str) -> None:
    await client.stub.open_url(OpenUrlRequest(url=url))
