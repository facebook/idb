#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.types import CompanionInfo
from idb.grpc.idb_pb2 import CompanionInfo as GrpcCompanionInfo


def companion_to_grpc(companion: CompanionInfo) -> GrpcCompanionInfo:
    return GrpcCompanionInfo(
        udid=companion.udid,
        host=companion.host,
        grpc_port=companion.port,
        is_local=companion.is_local,
    )


def companion_to_py(companion: GrpcCompanionInfo) -> CompanionInfo:
    return CompanionInfo(
        udid=companion.udid,
        host=companion.host,
        port=companion.grpc_port,
        is_local=companion.is_local,
    )
