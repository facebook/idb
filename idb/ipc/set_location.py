#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


from idb.grpc.types import CompanionClient
from idb.grpc.idb_pb2 import Location, SetLocationRequest


async def client(client: CompanionClient, latitude: float, longitude: float) -> None:
    await client.stub.set_location(
        SetLocationRequest(location=Location(latitude=latitude, longitude=longitude))
    )
