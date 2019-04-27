#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.grpc.types import CompanionClient
from idb.grpc.ipc_loader import DaemonContext
from idb.grpc.idb_pb2 import BootRequest, BootResponse
from idb.utils.typing import none_throws


async def client(client: CompanionClient) -> None:
    await client.stub.boot(BootRequest())


async def daemon(
    context: DaemonContext, client: CompanionClient, request: BootRequest
) -> BootResponse:
    if client.is_companion_available:
        await none_throws(context.boot_manager).boot(udid=none_throws(client.udid))
        return BootResponse()
    else:
        # TODO T41660845
        raise GRPCError(
            status=Status(Status.UNIMPLEMENTED),
            message="boot with chained daemons hasn't been implemented yet",
        )
