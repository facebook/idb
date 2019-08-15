#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.idb_pb2 import ListTargetsRequest, ListTargetsResponse
from idb.grpc.ipc_loader import DaemonContext
from idb.ipc.mapping.target import target_to_grpc


async def daemon(
    context: DaemonContext, request: ListTargetsRequest
) -> ListTargetsResponse:
    targets = context.companion_manager.targets
    return ListTargetsResponse(targets=[target_to_grpc(target) for target in targets])
