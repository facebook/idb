#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
from logging import Logger
from typing import Any, AsyncIterator, Dict, Generic, Optional, TypeVar

from idb.utils.typing import none_throws


_TSend = TypeVar("_TSend")
_TRecv = TypeVar("_TRecv")


# pyre-fixme[13]: Attribute `metadata` is never initialized.
class Stream(Generic[_TSend, _TRecv], AsyncIterator[_TRecv]):
    metadata: Dict[str, str]

    async def recv_message(self) -> Optional[_TRecv]:
        ...

    async def send_message(self, message: _TSend) -> None:
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
        # pyre-fixme[7]: Expected `_TRecv` but got `object`.
        return response


async def generate_bytes(
    stream: AsyncIterator[Any],  # pyre-ignore
) -> AsyncIterator[bytes]:
    async for response in stream:
        yield response.payload.data


async def stop_wrapper(
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
            return
        else:
            yield read.result()


async def cancel_wrapper(
    stream: Stream[_TSend, _TRecv], stop: asyncio.Event
) -> AsyncIterator[_TRecv]:
    async for event in stop_wrapper(stream, stop):
        yield event
    if stop.is_set():
        await stream.cancel()


async def join_streams(
    in_stream: Stream[_TSend, _TRecv], out_stream: Stream[_TRecv, _TSend]
) -> None:
    started_future = asyncio.Future()
    await asyncio.gather(
        _pipe_to_companion(in_stream, out_stream, started_future),
        _pipe_to_client(out_stream, in_stream, started_future),
    )


async def _pipe_to_companion(
    in_stream: Stream[_TSend, _TRecv],
    out_stream: Stream[_TRecv, _TSend],
    started_future: asyncio.Future,
) -> None:
    async for message in in_stream:
        await out_stream.send_message(message)
        if not started_future.done():
            started_future.set_result(None)
    await out_stream.end()


async def _pipe_to_client(
    in_stream: Stream[_TRecv, _TSend],
    out_stream: Stream[_TSend, _TRecv],
    started_future: asyncio.Future,
) -> None:
    await started_future
    async for message in in_stream:
        await out_stream.send_message(message)
