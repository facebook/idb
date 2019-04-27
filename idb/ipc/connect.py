#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import Dict, Optional

from idb.grpc.types import CompanionClient
from idb.grpc.ipc_loader import DaemonContext
from idb.common.types import ConnectionDestination, ConnectResponse
from idb.grpc.idb_pb2 import (
    ConnectRequest as GrpcConnectRequest,
    ConnectResponse as GrpcConnectResponse,
)
from idb.ipc.mapping.companion import companion_to_grpc, companion_to_py
from idb.ipc.mapping.destination import destination_to_grpc, destination_to_py
from idb.utils.typing import none_throws


async def client(
    client: CompanionClient,
    destination: ConnectionDestination,
    metadata: Optional[Dict[str, str]] = None,
) -> ConnectResponse:
    client.logger.debug(f"Connecting to {destination} with meta {metadata}")
    response = await client.stub.connect(
        GrpcConnectRequest(
            destination=destination_to_grpc(destination), metadata=metadata
        )
    )
    return companion_to_py(response.companion)


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
        return GrpcConnectResponse(companion=companion_to_grpc(companion))
