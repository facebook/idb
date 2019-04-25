#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.types import CompanionInfo
from idb.grpc.idb_pb2 import CompanionInfo as GrpcCompanionInfo


def companion_to_grpc(companion: CompanionInfo) -> GrpcCompanionInfo:
    return GrpcCompanionInfo(
        udid=companion.udid,
        host=companion.host,
        port=companion.port,
        is_local=companion.is_local,
        grpc_port=companion.grpc_port,
    )


def companion_to_py(companion: GrpcCompanionInfo) -> CompanionInfo:
    return CompanionInfo(
        udid=companion.udid,
        host=companion.host,
        port=companion.port,
        is_local=companion.is_local,
        grpc_port=companion.grpc_port,
    )
