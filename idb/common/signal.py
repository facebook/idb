#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import signal
from logging import Logger
from sys import stderr
from typing import AsyncGenerator, Sequence, TypeVar


_SIGNALS: Sequence[signal.Signals] = [signal.SIGTERM, signal.SIGINT]


def signal_handler_event(name: str) -> asyncio.Event:
    loop = asyncio.get_event_loop()
    stop: asyncio.Event = asyncio.Event()

    def signal_handler(sig: signal.Signals) -> None:
        print(f"\nStopping {name}", file=stderr)
        stop.set()

    for sig in _SIGNALS:
        loop.add_signal_handler(sig, lambda: signal_handler(sig))

    print(f"Running {name} until ^C", file=stderr)
    return stop


T = TypeVar("T")


async def signal_handler_generator(
    iterable: AsyncGenerator[T, None], name: str, logger: Logger
) -> AsyncGenerator[T, None]:
    async def _close() -> None:
        try:
            await iterable.aclose()
        except Exception:
            pass

    event = signal_handler_event(name=name)
    stop_future = asyncio.ensure_future(event.wait())

    while True:
        consume = asyncio.ensure_future(iterable.__anext__())
        done, pending = await asyncio.wait(
            [stop_future, consume], return_when=asyncio.FIRST_COMPLETED
        )
        if stop_future in done:
            await _close()
            consume.cancel()
            return
        try:
            yield consume.result()
        except StopAsyncIteration:
            await _close()
            return
