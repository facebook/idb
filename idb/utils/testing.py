#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-ignore-all-errors

import asyncio
import functools
import inspect
import unittest
import unittest.mock as _mock
import warnings
from collections.abc import Awaitable, Callable
from typing import cast, TypeVar


_RT = TypeVar("_RT")  # Return Generic
FuncType = Callable[..., Awaitable[_RT]]
_F = TypeVar("_F", bound=FuncType)  # Function Generic


def _tasks_warning(task_set):
    if task_set:
        warnings.warn(
            "There are tasks already on the event loop before running "
            f"the testmethod: {task_set}",
            stacklevel=0,
        )
        warnings.warn(
            "This may mean that something is creating tasks at import time",
            stacklevel=0,
        )


def awaitable(func: _F) -> _F:
    """
    What ever we are decorating, make it awaitable.
    This is not pretty, but useful when we don't know what
    we are accepting, like for unittests methods
    """

    @functools.wraps(func)
    async def new_func(*args, **kws):
        result = func(*args, **kws)
        if inspect.isawaitable(result):
            return await result
        return result

    return cast(_F, new_func)


# Prefer later.unittest.TestCase at Meta for task leak detection and modern async support.
# Fall back to stdlib IsolatedAsyncioTestCase for OSS or environments without later.
try:
    import later.unittest as _later_unittest  # type: ignore[import-not-found]

    _BaseTestCase = _later_unittest.TestCase
except ImportError:
    _BaseTestCase = unittest.IsolatedAsyncioTestCase


class TestCase(_BaseTestCase):
    """
    Modernized test case using later.unittest.TestCase at Meta,
    falling back to unittest.IsolatedAsyncioTestCase.
    No eager event loop creation in __init__ to avoid import-time side effects.
    See D109553234 / D109554536.
    """

    # Backward compatibility: some old code accesses self.loop directly.
    # later unittest / IsolatedAsyncioTestCase manage loop lifecycle automatically.
    # Provide property returning running loop, no eager creation.
    # If you need loop in setUpClass, move logic to asyncSetUp or wrap with
    # asyncio.run() — do not manually create event loops in tests.
    @property
    def loop(self) -> asyncio.AbstractEventLoop:
        return asyncio.get_running_loop()

    @loop.setter
    def loop(self, value: asyncio.AbstractEventLoop) -> None:
        # No-op setter for backward compatibility. Test framework manages loop.
        return


class AsyncMock(_mock.Mock):
    """Mock subclass which can be awaited on. Use this as new_callable
    to patch calls on async functions. Can also be used as an async context
    manager - returns self.
    """

    def __call__(self, *args, **kwargs):
        sup = super()

        async def coro():
            return sup.__call__(*args, **kwargs)

        return coro()

    def __await__(self):
        # Calling await on a Mock/AsyncMock object will result in
        # a TypeError. Instead, return the coroutine created above
        # to be awaited on
        return self().__await__()

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        pass


class AsyncContextManagerMock:
    """
    Helper mocking class to handle context manager consturcts.
    Example of usage:
    async def target():
        async with aiofiles.open('/tmp/b.txt') as f:
            return await f.read()

    class TestContextManager(TestCase):
            async def test_1(self):
                m = AsyncMock()
                m.read.return_value = 'fff'
                with async_mock.patch(
                    'aiofiles.open',
                    return_value=AsyncContextManagerMock(return_value=m)
                ):
                    r = await target()
                    self.assertEqual(r, 'fff')
    """

    def __init__(self, *args, **kwargs):
        self._mock = AsyncMock(*args, **kwargs)

    async def __aenter__(self, *args, **kwargs):
        return await self._mock(*args, **kwargs)

    async def __aexit__(self, exc_type, exc, tb):
        pass


def ignoreTaskLeaks(test_item):
    test_item.__unittest_asyncio_taskleaks__ = True
    return test_item
