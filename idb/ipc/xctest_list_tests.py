#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.manager.companion import CompanionClient
from idb.grpc.idb_pb2 import XctestListTestsRequest


async def list_test_bundle(client: CompanionClient, test_bundle_id: str) -> List[str]:
    response = await client.stub.xctest_list_tests(
        XctestListTestsRequest(bundle_name=test_bundle_id)
    )
    return [name for name in response.names]


CLIENT_PROPERTIES = [list_test_bundle]  # pyre-ignore
