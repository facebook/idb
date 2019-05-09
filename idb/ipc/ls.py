#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.common.types import FileEntryInfo
from idb.grpc.idb_pb2 import LsRequest
from idb.grpc.types import CompanionClient


async def client(
    client: CompanionClient, bundle_id: str, path: str
) -> List[FileEntryInfo]:
    response = await client.stub.ls(LsRequest(bundle_id=bundle_id, path=path))
    return [FileEntryInfo(path=file.path) for file in response.files]
