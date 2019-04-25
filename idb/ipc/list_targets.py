#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.manager.companion import CompanionClient
from idb.grpc.ipc_loader import DaemonContext
from idb.common.types import TargetDescription
from idb.grpc.idb_pb2 import ListTargetsRequest, ListTargetsResponse
from idb.ipc.mapping.target import target_to_grpc, target_to_py


async def client(client: CompanionClient) -> List[TargetDescription]:
    response = await client.stub.list_targets(ListTargetsRequest())
    return [target_to_py(target) for target in response.targets]


async def daemon(
    context: DaemonContext, request: ListTargetsRequest
) -> ListTargetsResponse:
    targets = context.companion_manager.targets
    return ListTargetsResponse(targets=[target_to_grpc(target) for target in targets])
