#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import Dict, Optional

from idb.common.types import ConnectionDestination
from idb.grpc.idb_pb2 import (
    ConnectRequest as GrpcConnectRequest,
    ConnectResponse as GrpcConnectResponse,
)
from idb.grpc.ipc_loader import DaemonContext
from idb.ipc.mapping.companion import companion_to_grpc
from idb.ipc.mapping.destination import destination_to_py
from idb.utils.typing import none_throws


async def daemon(
    context: DaemonContext, request: GrpcConnectRequest
) -> GrpcConnectResponse:
    destination = destination_to_py(none_throws(request.destination))
    return await connect_companion(context, destination, request.metadata)


async def connect_companion(
    context: DaemonContext,
    destination: ConnectionDestination,
    metadata: Optional[Dict[str, str]],
) -> GrpcConnectResponse:
    async with context.companion_manager.create_companion_for_target_with_destination(
        destination=destination, metadata=metadata
    ) as companion:
        # temporarily write to direct_companion_manager while we transition to daemonless
        context.direct_companion_manager.add_companion(companion)
        return GrpcConnectResponse(companion=companion_to_grpc(companion))
