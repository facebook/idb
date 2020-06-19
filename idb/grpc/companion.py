#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from typing import List, Sequence

from idb.common.types import Address, CompanionInfo, TargetDescription
from idb.grpc.idb_pb2 import CompanionInfo as GrpcCompanionInfo


def companion_to_grpc(companion: CompanionInfo) -> GrpcCompanionInfo:
    return GrpcCompanionInfo(
        udid=companion.udid,
        host=companion.address.host,
        grpc_port=companion.address.port,
        is_local=companion.is_local,
    )


def companion_to_py(companion: GrpcCompanionInfo) -> CompanionInfo:
    return CompanionInfo(
        udid=companion.udid,
        address=Address(host=companion.host, port=companion.grpc_port),
        is_local=companion.is_local,
    )


def merge_connected_targets(
    local_targets: Sequence[TargetDescription],
    connected_targets: Sequence[TargetDescription],
) -> List[TargetDescription]:
    connected_mapping = {target.udid: target for target in connected_targets}
    targets = {}
    # First, add all local targets, updating companion info where available
    for target in local_targets:
        udid = target.udid
        if udid in connected_mapping:
            targets[udid] = connected_mapping[udid]
        else:
            targets[udid] = target
    # Then add the connected targets that aren't local
    for target in connected_targets:
        udid = target.udid
        if udid in targets:
            continue
        targets[udid] = target
    return list(targets.values())
