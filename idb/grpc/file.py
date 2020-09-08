#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
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
        return GrpcFileContainer(kind=GrpcFileContainer.MEDIA, bundle_id=None)
    if container == FileContainerType.CRASHES:
        return GrpcFileContainer(kind=GrpcFileContainer.CRASHES, bundle_id=None)
    if container == FileContainerType.ROOT:
        return GrpcFileContainer(kind=GrpcFileContainer.ROOT, bundle_id=None)
    if container == FileContainerType.PROVISIONING_PROFILES:
        return GrpcFileContainer(
            kind=GrpcFileContainer.PROVISIONING_PROFILES, bundle_id=None
        )
    return GrpcFileContainer(kind=GrpcFileContainer.NONE, bundle_id=None)


def container_to_bundle_id_deprecated(container: FileContainer) -> str:
    if isinstance(container, str):
        return container
    return ""
