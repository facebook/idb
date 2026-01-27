#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-ignore-all-errors

import asyncio
import functools
import inspect
import sys
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


class TestCase(unittest.TestCase):
    def __init__(self, methodName="runTest", loop=None):
        self.loop = loop or asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self.loop.set_debug(True)
        super().__init__(methodName)

    async def _run_test_method(self, testMethod, result, expecting_failure):
        """Run setUp, test method, and tearDown with proper error handling."""
        success = True
        skipped = []
        errors = []
        expected_failure = None

        # Run setUp
        try:
            await awaitable(self.setUp)()
        except unittest.SkipTest as e:
            success = False
            skipped.append((self, str(e)))
        except Exception:
            success = False
            errors.append((self, sys.exc_info()))

        # Run test method if setUp succeeded
        if success:
            try:
                await awaitable(testMethod)()
            except unittest.SkipTest as e:
                success = False
                skipped.append((self, str(e)))
            except Exception:
                exc_info = sys.exc_info()
                if expecting_failure:
                    expected_failure = exc_info
                else:
                    success = False
                    errors.append((self, exc_info))

            # Run tearDown
            try:
                await awaitable(self.tearDown)()
            except unittest.SkipTest as e:
                success = False
                skipped.append((self, str(e)))
            except Exception:
                success = False
                errors.append((self, sys.exc_info()))

        # Run cleanups
        while self._cleanups:
            function, args, kwargs = self._cleanups.pop()
            try:
                await awaitable(function)(*args, **kwargs)
            except Exception:
                success = False
                errors.append((self, sys.exc_info()))

        return success, skipped, errors, expected_failure

    async def doCleanups(self):
        while self._cleanups:
            function, args, kwargs = self._cleanups.pop()
            try:
                await awaitable(function)(*args, **kwargs)
            except Exception:
                pass

    async def debug_async(self, testMethod):
        await awaitable(self.setUp)()
        await awaitable(testMethod)()
        await awaitable(self.tearDown)()
        while self._cleanups:
            function, args, kwargs = self._cleanups.pop(-1)
            await awaitable(function)(*args, **kwargs)

    def asyncio_orchestration_debug(self, testMethod):
        asyncio.set_event_loop(self.loop)
        # Don't make testmethods cleanup tasks that existed before them
        before_tasks = asyncio.all_tasks(self.loop)
        _tasks_warning(before_tasks)
        debug_async = self.debug_async(testMethod)
        self.loop.run_until_complete(debug_async)

        # Sometimes we end up with a reference to our task for debug_async
        tasks = {
            t
            for t in asyncio.all_tasks(self.loop) - before_tasks
            if not (t._coro == debug_async and t.done())
        }
        del before_tasks
        self.assertEqual(set(), tasks, "left over asyncio tasks!")

    def _run_async_test(self, testMethod, result, expecting_failure):
        """Run the async test with proper asyncio orchestration."""
        asyncio.set_event_loop(self.loop)

        # Don't make testmethods cleanup tasks that existed before them
        before_tasks = asyncio.all_tasks(self.loop)
        _tasks_warning(before_tasks)

        run_coro = self._run_test_method(testMethod, result, expecting_failure)
        ignore_tasks = getattr(
            testMethod, "__unittest_asyncio_taskleaks__", False
        ) or getattr(self, "__unittest_asyncio_taskleaks__", False)

        success = True
        skipped = []
        errors = []
        expected_failure = None

        try:
            success, skipped, errors, expected_failure = self.loop.run_until_complete(
                run_coro
            )

            # Sometimes we end up with a reference to our task for run_coro
            tasks = {
                t
                for t in asyncio.all_tasks(self.loop) - before_tasks
                if not (t._coro == run_coro and t.done())
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
        except unittest.SkipTest as e:
            success = False
            skipped.append((self, str(e)))
        except Exception:
            exc_info = sys.exc_info()
            if expecting_failure:
                expected_failure = exc_info
            else:
                success = False
                errors.append((self, exc_info))

        return success, skipped, errors, expected_failure

    # pyre-ignore
    def run(self, result=None):
        """
        Run the test case with asyncio support.
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
                result.addSkip(self, skip_why)
            finally:
                result.stopTest(self)
            return None

        expecting_failure_method = getattr(
            testMethod, "__unittest_expecting_failure__", False
        )
        expecting_failure_class = getattr(self, "__unittest_expecting_failure__", False)
        expecting_failure = expecting_failure_class or expecting_failure_method

        try:
            success, skipped, errors, expected_failure = self._run_async_test(
                testMethod, result, expecting_failure
            )

            for test, reason in skipped:
                result.addSkip(test, reason)

            for test, exc_info in errors:
                if exc_info is not None:
                    result.addError(test, exc_info)

            if success:
                if expecting_failure:
                    if expected_failure:
                        result.addExpectedFailure(self, expected_failure)
                    else:
                        result.addUnexpectedSuccess(self)
                else:
                    result.addSuccess(self)
            return result
        finally:
            result.stopTest(self)
            if orig_result is None:
                stopTestRun = getattr(result, "stopTestRun", None)
                if stopTestRun is not None:
                    stopTestRun()

    # pyre-ignore
    def debug(self):
        self.asyncio_orchestration_debug(getattr(self, self._testMethodName))


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
