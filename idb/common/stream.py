#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import AsyncIterator, Callable, TypeVar


_A = TypeVar("_A")
_B = TypeVar("_B")


async def stream_map(
    iterator: AsyncIterator[_A], function: Callable[[_A], _B]
) -> AsyncIterator[_B]:
    async for item in iterator:
        yield function(item)
