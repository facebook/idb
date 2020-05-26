#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.types import CompanionInfo, ScreenDimensions, TargetDescription
from idb.grpc.companion import companion_to_grpc
from idb.grpc.idb_pb2 import (
    ScreenDimensions as GrpcScreenDimensions,
    TargetDescription as GrpcTargetDescription,
)


def target_to_grpc(target: TargetDescription) -> GrpcTargetDescription:
    screen_dimensions = target.screen_dimensions
    companion_info = target.companion_info
    return GrpcTargetDescription(
        udid=target.udid,
        name=target.name,
        screen_dimensions=(
            screen_dimensions_to_grpc(screen_dimensions)
            if screen_dimensions is not None
            else None
        ),
        state=target.state,
        target_type=target.target_type,
        os_version=target.os_version,
        architecture=target.architecture,
        companion_info=(
            companion_to_grpc(companion_info) if companion_info is not None else None
        ),
    )


def target_to_py(
    target: GrpcTargetDescription, companion: CompanionInfo
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
