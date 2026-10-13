#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
from asyncio import StreamReader, StreamWriter

from idb.common.types import IdbException
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import ForwardPortRequest, ForwardPortResponse
from idb.grpc.stream import Stream

CHUNK_SIZE = 64 * 1024


async def forward_port(
    stub: CompanionServiceStub,
    device_port: int,
    input_stream: StreamReader,
    output_stream: StreamWriter,
) -> None:
    """One socket connection, without retries or ownership of the local streams."""
    if not 1 <= device_port <= 65535:
        raise IdbException("Device port must be in 1...65535")
    async with stub.forward_port.open() as stream:
        await stream.send_message(
            ForwardPortRequest(open=ForwardPortRequest.Open(port=device_port))
        )
        response = await stream.recv_message()
        if response is None or response.WhichOneof("event") != "opened":
            raise IdbException("Companion did not acknowledge device port connection")
        send = asyncio.create_task(_send(stream, input_stream))
        receive = asyncio.create_task(_receive(stream, output_stream))
        tasks = [send, receive]
        try:
            completed, _ = await asyncio.wait(
                tasks, return_when=asyncio.FIRST_COMPLETED
            )
            for task in completed:
                task.result()
            if send not in completed:
                send.cancel()
                await asyncio.gather(send, return_exceptions=True)
            await stream.end()
            if receive not in completed:
                await receive
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)


async def _send(
    stream: Stream[ForwardPortRequest, ForwardPortResponse], reader: StreamReader
) -> None:
    while data := await reader.read(CHUNK_SIZE):
        await stream.send_message(ForwardPortRequest(data=data))


async def _receive(
    stream: Stream[ForwardPortRequest, ForwardPortResponse], writer: StreamWriter
) -> None:
    while response := await stream.recv_message():
        event = response.WhichOneof("event")
        if event != "data":
            raise IdbException(f"Unexpected forwarding response: {event}")
        if len(response.data) > CHUNK_SIZE:
            raise IdbException("Companion sent a forwarding chunk larger than 64 KiB")
        writer.write(response.data)
        await writer.drain()
