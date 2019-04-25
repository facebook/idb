#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.types import ScreenDimensions, TargetDescription
from idb.grpc.idb_pb2 import (
    ScreenDimensions as GrpcScreenDimensions,
    TargetDescription as GrpcTargetDescription,
)
from idb.ipc.mapping.companion import companion_to_grpc, companion_to_py


def target_to_grpc(target: TargetDescription) -> GrpcTargetDescription:
    return GrpcTargetDescription(
        udid=target.udid,
        name=target.name,
        screen_dimensions=screen_dimensions_to_grpc(target.screen_dimensions)
        if target.screen_dimensions
        else None,
        state=target.state,
        target_type=target.target_type,
        os_version=target.os_version,
        architecture=target.architecture,
        companion_info=companion_to_grpc(target.companion_info)
        if target.companion_info
        else None,
        daemon_host=None,
        daemon_port=None,
    )


def target_to_py(target: GrpcTargetDescription) -> TargetDescription:
    return TargetDescription(
        udid=target.udid,
        name=target.name,
        screen_dimensions=screen_dimensions_to_py(target.screen_dimensions)
        if target.screen_dimensions
        else None,
        state=target.state,
        target_type=target.target_type,
        os_version=target.os_version,
        architecture=target.architecture,
        companion_info=companion_to_py(target.companion_info)
        if target.companion_info
        else None,
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
