#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
from logging import Logger
from typing import Any, AsyncIterator, Dict, Generic, Optional, TypeVar

from idb.utils.typing import none_throws


_TSend = TypeVar("_TSend")
_TRecv = TypeVar("_TRecv")


class Stream(Generic[_TSend, _TRecv], AsyncIterator[_TRecv]):
    metadata: Dict[str, str]  # pyre-ignore

    async def recv_message(self) -> Optional[_TRecv]:
        ...

    async def send_message(self, message: _TSend, end: bool = False) -> None:
        ...

    async def end(self) -> None:
        ...

    async def cancel(self) -> None:
        ...


async def drain_to_stream(
    stream: Stream[_TSend, _TRecv], generator: AsyncIterator[_TSend], logger: Logger
) -> _TRecv:
    while True:
        async for message in generator:
            await stream.send_message(message)
        await stream.end()
        logger.debug(f"Streamed all chunks to companion, waiting for completion")
        response = none_throws(await stream.recv_message())
        logger.debug(f"Companion completed")
        return response


async def generate_bytes(
    stream: AsyncIterator[Any],  # pyre-ignore
) -> AsyncIterator[bytes]:
    async for response in stream:
        yield response.payload.data


async def cancel_wrapper(
    stream: Stream[_TSend, _TRecv], stop: asyncio.Event
) -> AsyncIterator[_TRecv]:
    stop_future = asyncio.ensure_future(stop.wait())
    while True:
        read = asyncio.ensure_future(stream.recv_message())
        done, pending = await asyncio.wait(
            [stop_future, read], return_when=asyncio.FIRST_COMPLETED
        )
        if stop_future in done:
            read.cancel()
            await stream.cancel()
            return
        else:
            yield read.result()
