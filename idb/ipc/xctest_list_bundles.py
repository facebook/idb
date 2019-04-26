#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.manager.companion import CompanionClient
from idb.common.types import InstalledTestInfo
from idb.grpc.idb_pb2 import XctestListBundlesRequest


async def list_xctests(client: CompanionClient) -> List[InstalledTestInfo]:
    response = await client.stub.xctest_list_bundles(XctestListBundlesRequest())
    return [
        InstalledTestInfo(
            bundle_id=bundle.bundle_id,
            name=bundle.name,
            architectures=bundle.architectures,
        )
        for bundle in response.bundles
    ]


CLIENT_PROPERTIES = [list_xctests]  # pyre-ignore
