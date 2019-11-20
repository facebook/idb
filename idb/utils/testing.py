#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import functools
import inspect
import logging
import unittest
import unittest.mock as _mock
import warnings
from typing import Awaitable, Callable, TypeVar, cast

# pyre-ignore
from unittest.case import _Outcome


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


class TestCase(unittest.TestCase):
    def __init__(self, methodName="runTest", loop=None):
        self.loop = loop or asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.set_debug(True)
        super().__init__(methodName)

    async def run_async(self, testMethod, outcome, expecting_failure):
        with outcome.testPartExecutor(self):
            await awaitable(self.setUp)()
        if outcome.success:
            outcome.expecting_failure = expecting_failure
            with outcome.testPartExecutor(self, isTest=True):
                await awaitable(testMethod)()
            outcome.expecting_failure = False
            with outcome.testPartExecutor(self):
                await awaitable(self.tearDown)()
        await self.doCleanups()

    async def doCleanups(self):
        outcome = self._outcome or _Outcome()
        while self._cleanups:
            function, args, kwargs = self._cleanups.pop()
            with outcome.testPartExecutor(self):
                await awaitable(function)(*args, **kwargs)

    async def debug_async(self, testMethod):
        await awaitable(self.setUp)()
        await awaitable(testMethod)()
        await awaitable(self.tearDown)()
        while self._cleanups:
            function, args, kwargs = self._cleanups.pop(-1)
            await awaitable(function)(*args, **kwargs)

    @_mock.patch("asyncio.base_events.logger")
    @_mock.patch("asyncio.coroutines.logger")
    def asyncio_orchestration_debug(self, testMethod, b_log, c_log):
        asyncio.set_event_loop(self.loop)
        real_logger = logging.getLogger("asyncio").error
        c_log.error.side_effect = b_log.error.side_effect = real_logger
        # Don't make testmethods cleanup tasks that existed before them
        before_tasks = asyncio.all_tasks(self.loop)
        _tasks_warning(before_tasks)
        debug_async = self.debug_async(testMethod)
        self.loop.run_until_complete(debug_async)

        if c_log.error.called or b_log.error.called:
            self.fail("asyncio logger.error() called!")
        # Sometimes we end up with a reference to our task for debug_async
        tasks = {
            t
            for t in asyncio.all_tasks(self.loop) - before_tasks
            if not (t._coro == debug_async and t.done())
        }
        del before_tasks
        self.assertEqual(set(), tasks, "left over asyncio tasks!")

    @_mock.patch("asyncio.base_events.logger")
    @_mock.patch("asyncio.coroutines.logger")
    def asyncio_orchestration_outcome(
        self, testMethod, outcome, expecting_failure, b_log, c_log
    ):
        asyncio.set_event_loop(self.loop)
        real_logger = logging.getLogger("asyncio").error
        c_log.error.side_effect = b_log.error.side_effect = real_logger
        # Don't make testmethods cleanup tasks that existed before them
        before_tasks = asyncio.all_tasks(self.loop)
        _tasks_warning(before_tasks)
        run_async = self.run_async(testMethod, outcome, expecting_failure)
        ignore_tasks = getattr(
            testMethod, "__unittest_asyncio_taskleaks__", False
        ) or getattr(self, "__unittest_asyncio_taskleaks__", False)
        with outcome.testPartExecutor(self):
            self.loop.run_until_complete(run_async)
            # Restore expecting_faiures so we can test the below
            outcome.expecting_failure = expecting_failure
            if c_log.error.called or b_log.error.called:
                self.fail("asyncio logger.error() called!")

            # Sometimes we end up with a reference to our task for run_async
            tasks = {
                t
                for t in asyncio.all_tasks(self.loop) - before_tasks
                if not (t._coro == run_async and t.done())
            }
            del before_tasks
            if ignore_tasks and tasks:
                warnings.warn(
                    "There are left over asyncio tasks after running "
                    f"testmethod: {tasks}",
                    stacklevel=0,
                )
            else:
                self.assertEqual(set(), tasks, "left over asyncio tasks!")

    # pyre-ignore
    def run(self, result=None):
        """
        This is a complete copy of TestCase.run
        But with some asyncio worked into it.
        """
        orig_result = result
        if result is None:
            result = self.defaultTestResult()
            startTestRun = getattr(result, "startTestRun", None)
            if startTestRun is not None:
                startTestRun()

        result.startTest(self)

        testMethod = getattr(self, self._testMethodName)
        if getattr(self.__class__, "__unittest_skip__", False) or getattr(
            testMethod, "__unittest_skip__", False
        ):
            # If the class or method was skipped.
            try:
                skip_why = getattr(
                    self.__class__, "__unittest_skip_why__", ""
                ) or getattr(testMethod, "__unittest_skip_why__", "")
                self._addSkip(result, self, skip_why)  # noqa T484
            finally:
                result.stopTest(self)
            return None
        expecting_failure_method = getattr(
            testMethod, "__unittest_expecting_failure__", False
        )
        expecting_failure_class = getattr(self, "__unittest_expecting_failure__", False)
        expecting_failure = expecting_failure_class or expecting_failure_method
        outcome = _Outcome(result)
        try:
            self._outcome = outcome

            self.asyncio_orchestration_outcome(testMethod, outcome, expecting_failure)

            for test, reason in outcome.skipped:
                self._addSkip(result, test, reason)  # noqa T484
            self._feedErrorsToResult(result, outcome.errors)  # noqa T484
            if outcome.success:
                if expecting_failure:
                    if outcome.expectedFailure:
                        self._addExpectedFailure(  # noqa T484
                            result, outcome.expectedFailure
                        )
                    else:
                        self._addUnexpectedSuccess(result)  # noqa T484
                else:
                    result.addSuccess(self)
            return result
        finally:
            result.stopTest(self)
            if orig_result is None:
                stopTestRun = getattr(result, "stopTestRun", None)
                if stopTestRun is not None:
                    stopTestRun()

            # explicitly break reference cycles:
            # outcome.errors -> frame -> outcome -> outcome.errors
            # outcome.expectedFailure -> frame -> outcome -> outcome.expectedFailure
            outcome.errors.clear()
            outcome.expectedFailure = None

            # clear the outcome, no more needed
            self._outcome = None

    # pyre-ignore
    def debug(self):
        self.asyncio_orchestration_debug(getattr(self, self._testMethodName))


class AsyncMock(_mock.Mock):
    """ Mock subclass which can be awaited on. Use this as new_callable
    to patch calls on async functions. Can also be used as an async context
    manager - returns self.
    """

    def __call__(self, *args, **kwargs):
        sup = super(AsyncMock, self)

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
                    self.assertEquals(r, 'fff')
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
