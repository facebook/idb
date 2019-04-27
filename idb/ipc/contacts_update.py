#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.grpc.types import CompanionClient
from idb.common.tar import create_tar
from idb.grpc.idb_pb2 import ContactsUpdateRequest, Payload


async def client(client: CompanionClient, contacts_path: str) -> None:
    data = await create_tar([contacts_path])
    await client.stub.contacts_update(ContactsUpdateRequest(payload=Payload(data=data)))
