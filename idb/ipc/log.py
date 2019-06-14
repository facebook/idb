#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.


import asyncio
from typing import AsyncIterator, List, Optional

from idb.grpc.idb_pb2 import LogRequest, LogResponse
from idb.grpc.stream import Stream, cancel_wrapper, join_streams
from idb.grpc.types import CompanionClient


async def _tail_specific_logs(
    client: CompanionClient,
    source: LogRequest.Source,
    stop: asyncio.Event,
    arguments: Optional[List[str]],
) -> AsyncIterator[str]:
    async with client.stub.log.open() as stream:
        await stream.send_message(
            LogRequest(arguments=arguments, source=source), end=True
        )
        async for message in cancel_wrapper(stream=stream, stop=stop):
            yield message.output.decode()


async def tail_companion_logs(
    client: CompanionClient, stop: asyncio.Event
) -> AsyncIterator[str]:
    async for message in _tail_specific_logs(
        client=client, source=LogRequest.COMPANION, stop=stop, arguments=None
    ):
        yield message


async def tail_logs(
    client: CompanionClient, stop: asyncio.Event, arguments: Optional[List[str]] = None
) -> AsyncIterator[str]:
    async for message in _tail_specific_logs(
        client=client, source=LogRequest.TARGET, stop=stop, arguments=arguments
    ):
        yield message


async def daemon(
    client: CompanionClient, stream: Stream[LogRequest, LogResponse]
) -> None:
    async with client.stub.log.open() as out_stream:
        await join_streams(stream, out_stream)


CLIENT_PROPERTIES = [tail_logs, tail_companion_logs]  # pyre-ignore
