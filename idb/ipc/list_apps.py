#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import List

from idb.grpc.types import CompanionClient
from idb.common.types import AppProcessState, InstalledAppInfo
from idb.grpc.idb_pb2 import ListAppsRequest


async def client(client: CompanionClient) -> List[InstalledAppInfo]:
    response = await client.stub.list_apps(ListAppsRequest())
    return [
        InstalledAppInfo(
            bundle_id=app.bundle_id,
            name=app.name,
            architectures=app.architectures,
            install_type=app.install_type,
            process_state=AppProcessState(app.process_state),
            debuggable=app.debuggable,
        )
        for app in response.apps
    ]
