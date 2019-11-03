#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import AsyncIterator, Callable, TypeVar


_A = TypeVar("_A")
_B = TypeVar("_B")


async def stream_map(
    iterator: AsyncIterator[_A], function: Callable[[_A], _B]
) -> AsyncIterator[_B]:
    async for item in iterator:
        yield function(item)
