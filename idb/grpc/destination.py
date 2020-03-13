#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from idb.common.types import Address, ConnectionDestination
from idb.grpc.idb_pb2 import (
    ConnectionAddress as GrpcConnectionAddress,
    ConnectionDestination as GrpcConnectionDestination,
)


def destination_to_grpc(
    destination: ConnectionDestination
) -> GrpcConnectionDestination:
    if isinstance(destination, str):
        return GrpcConnectionDestination(target_udid=destination)
    elif isinstance(destination, Address):
        return GrpcConnectionDestination(
            address=GrpcConnectionAddress(host=destination.host, port=destination.port)
        )


def destination_to_py(destination: GrpcConnectionDestination) -> ConnectionDestination:
    if destination.HasField("address"):
        return Address(host=destination.address.host, port=destination.address.port)
    else:
        return destination.target_udid
