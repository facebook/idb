#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.common.types import CrashLogInfo, CrashLogQuery
from idb.grpc.types import CompanionClient
from idb.ipc.mapping.crash import _to_crash_log_info_list, _to_crash_log_query_proto


async def client(client: CompanionClient, query: CrashLogQuery) -> List[CrashLogInfo]:
    response = await client.stub.crash_delete(_to_crash_log_query_proto(query))
    return _to_crash_log_info_list(response)
