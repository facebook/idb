#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.types import CompanionClient
from idb.grpc.ipc_loader import DaemonContext
from idb.common.types import ConnectionDestination
from idb.grpc.idb_pb2 import DisconnectRequest, DisconnectResponse
from idb.ipc.mapping.destination import destination_to_grpc, destination_to_py
from idb.utils.typing import none_throws


async def client(
    client: CompanionClient,
    destination: ConnectionDestination,
    disconnect_from_daemon: bool = False,
) -> None:
    await client.stub.disconnect(
        DisconnectRequest(
            destination=destination_to_grpc(destination),
            is_daemon=disconnect_from_daemon,
        )
    )


async def daemon(
    context: DaemonContext, request: DisconnectRequest
) -> DisconnectResponse:
    destination = destination_to_py(none_throws(request.destination))
    context.companion_manager.remove_companion(destination)
    return DisconnectResponse()
