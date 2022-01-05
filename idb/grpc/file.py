#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.types import FileContainer, FileContainerType
from idb.grpc.idb_pb2 import FileContainer as GrpcFileContainer


def container_to_grpc(container: FileContainer) -> GrpcFileContainer:
    if isinstance(container, str):
        return GrpcFileContainer(
            kind=GrpcFileContainer.APPLICATION, bundle_id=container
        )
    if container == FileContainerType.MEDIA:
        return GrpcFileContainer(kind=GrpcFileContainer.MEDIA)
    if container == FileContainerType.CRASHES:
        return GrpcFileContainer(kind=GrpcFileContainer.CRASHES)
    if container == FileContainerType.ROOT:
        return GrpcFileContainer(kind=GrpcFileContainer.ROOT)
    if container == FileContainerType.PROVISIONING_PROFILES:
        return GrpcFileContainer(kind=GrpcFileContainer.PROVISIONING_PROFILES)
    if container == FileContainerType.MDM_PROFILES:
        return GrpcFileContainer(kind=GrpcFileContainer.MDM_PROFILES)
    if container == FileContainerType.SPRINGBOARD_ICONS:
        return GrpcFileContainer(kind=GrpcFileContainer.SPRINGBOARD_ICONS)
    if container == FileContainerType.WALLPAPER:
        return GrpcFileContainer(kind=GrpcFileContainer.WALLPAPER)
    if container == FileContainerType.DISK_IMAGES:
        return GrpcFileContainer(kind=GrpcFileContainer.DISK_IMAGES)
    if container == FileContainerType.GROUP:
        return GrpcFileContainer(kind=GrpcFileContainer.GROUP_CONTAINER)
    if container == FileContainerType.APPLICATION:
        return GrpcFileContainer(kind=GrpcFileContainer.APPLICATION_CONTAINER)
    if container == FileContainerType.AUXILLARY:
        return GrpcFileContainer(kind=GrpcFileContainer.AUXILLARY)
    if container == FileContainerType.XCTEST:
        return GrpcFileContainer(kind=GrpcFileContainer.XCTEST)
    if container == FileContainerType.DYLIB:
        return GrpcFileContainer(kind=GrpcFileContainer.DYLIB)
    if container == FileContainerType.DSYM:
        return GrpcFileContainer(kind=GrpcFileContainer.DSYM)
    if container == FileContainerType.FRAMEWORK:
        return GrpcFileContainer(kind=GrpcFileContainer.FRAMEWORK)
    if container == FileContainerType.SYMBOLS:
        return GrpcFileContainer(kind=GrpcFileContainer.SYMBOLS)
    return GrpcFileContainer(kind=GrpcFileContainer.NONE)
