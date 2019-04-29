#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


import asyncio
from typing import AsyncIterator, List, Optional

from idb.grpc.idb_pb2 import LogRequest
from idb.grpc.stream import cancel_wrapper
from idb.grpc.types import CompanionClient


async def tail_logs(
    client: CompanionClient, stop: asyncio.Event, arguments: Optional[List[str]] = None
) -> AsyncIterator[str]:
    async with client.stub.log.open() as stream:
        await stream.send_message(LogRequest(arguments=arguments), end=True)
        async for message in cancel_wrapper(stream=stream, stop=stop):
            yield message.output.decode()


CLIENT_PROPERTIES = [tail_logs]  # pyre-ignore
