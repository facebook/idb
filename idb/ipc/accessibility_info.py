#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import Optional, Tuple

from idb.common.types import AccessibilityInfo
from idb.grpc.types import CompanionClient
from idb.grpc.idb_pb2 import AccessibilityInfoRequest, Point


async def client(
    client: CompanionClient, point: Optional[Tuple[int, int]]
) -> AccessibilityInfo:
    grpc_point = Point(x=point[0], y=point[1]) if point is not None else None
    response = await client.stub.accessibility_info(
        AccessibilityInfoRequest(point=grpc_point)
    )
    return AccessibilityInfo(json=response.json)
