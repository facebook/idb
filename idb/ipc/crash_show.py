#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.types import CrashLog
from idb.grpc.types import CompanionClient
from idb.grpc.idb_pb2 import CrashShowRequest
from idb.ipc.mapping.crash import _to_crash_log


async def client(client: CompanionClient, name: str) -> CrashLog:
    response = await client.stub.crash_show(CrashShowRequest(name=name))
    return _to_crash_log(response)
