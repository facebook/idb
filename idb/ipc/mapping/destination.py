#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

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
            address=GrpcConnectionAddress(
                host=destination.host,
                port=destination.port,
                grpc_port=destination.grpc_port,
            )
        )


def destination_to_py(destination: GrpcConnectionDestination) -> ConnectionDestination:
    if destination.HasField("address"):
        return Address(
            host=destination.address.host,
            port=destination.address.port,
            grpc_port=destination.address.grpc_port,
        )
    else:
        return destination.target_udid
