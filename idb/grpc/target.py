#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
from typing import List, Optional, Sequence

from idb.common.types import Address, CompanionInfo, ScreenDimensions, TargetDescription
from idb.grpc.idb_pb2 import (
    CompanionInfo as GrpcCompanionInfo,
    ScreenDimensions as GrpcScreenDimensions,
    TargetDescription as GrpcTargetDescription,
)


def target_to_py(
    target: GrpcTargetDescription, companion: CompanionInfo, metadata: bytes
) -> TargetDescription:
    return TargetDescription(
        udid=target.udid,
        name=target.name,
        screen_dimensions=(
            screen_dimensions_to_py(target.screen_dimensions)
            if target.screen_dimensions
            else None
        ),
        state=target.state,
        target_type=target.target_type,
        os_version=target.os_version,
        architecture=target.architecture,
        companion_info=companion,
        extended=(json.loads(target.extended.decode()) if len(target.extended) else {}),
        diagnostics=(
            json.loads(target.diagnostics.decode()) if len(target.diagnostics) else {}
        ),
        metadata=(json.loads(metadata.decode()) if len(metadata) else {}),
    )


def companion_to_py(
    companion: GrpcCompanionInfo, address: Address, is_local: Optional[bool]
) -> CompanionInfo:
    metadata = companion.metadata
    return CompanionInfo(
        address=address,
        udid=companion.udid,
        is_local=(is_local if is_local is not None else companion.is_local),
        metadata=(json.loads(metadata.decode()) if len(metadata) else {}),
    )


def screen_dimensions_to_grpc(dimensions: ScreenDimensions) -> GrpcScreenDimensions:
    return GrpcScreenDimensions(
        width=dimensions.width,
        height=dimensions.height,
        density=dimensions.density,
        width_points=dimensions.width_points,
        height_points=dimensions.height_points,
    )


def screen_dimensions_to_py(dimensions: GrpcScreenDimensions) -> ScreenDimensions:
    return ScreenDimensions(
        width=dimensions.width,
        height=dimensions.height,
        density=dimensions.density,
        width_points=dimensions.width_points,
        height_points=dimensions.height_points,
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
