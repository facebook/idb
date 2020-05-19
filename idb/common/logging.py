#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import functools
import inspect
import logging
import time
from concurrent.futures import CancelledError
from types import TracebackType
from typing import Any, AsyncContextManager, Collection, Optional, Tuple, Type

import idb.common.plugin as plugin
from idb.common.types import LoggingMetadata
from idb.utils.typing import none_throws


logger: logging.Logger = logging.getLogger("idb")


def _initial_info(
    args: Collection[Any], metadata: Optional[LoggingMetadata]  # pyre-ignore
) -> Tuple[LoggingMetadata, int]:
    _metadata: LoggingMetadata = metadata or {}
    if len(args):
        # pyre-fixme[16]: `Collection` has no attribute `__getitem__`.
        self_meta: Optional[LoggingMetadata] = getattr(args[0], "metadata", None)
        if self_meta:
            _metadata.update(self_meta)
    start = int(time.time())
    return (_metadata, start)


class log_call(AsyncContextManager[None]):
    def __init__(
        self, name: Optional[str] = None, metadata: Optional[LoggingMetadata] = None
    ) -> None:
        self.name = name
        self.metadata: LoggingMetadata = metadata or {}
        self.start: Optional[int] = None

    async def __aenter__(self) -> None:
        name = none_throws(self.name)
        logger.debug(f"{self.name} called")
        self.start = int(time.time())
        await plugin.before_invocation(name=name, metadata=self.metadata)

    async def __aexit__(
        self,
        exc_type: Optional[Type[Exception]],
        exception: Optional[Exception],
        traceback: Optional[TracebackType],
    ) -> bool:
        name = none_throws(self.name)
        duration = int((time.time() - none_throws(self.start)) * 1000)
        if exception:
            logger.debug(f"{name} failed")
            await plugin.failed_invocation(
                name=name,
                duration=duration,
                exception=exception,
                metadata=self.metadata,
            )
        else:
            logger.debug(f"{name} succeeded")
            await plugin.after_invocation(
                name=name, duration=duration, metadata=self.metadata
            )
        return False

    def __call__(self, function) -> Any:  # pyre-ignore
        _name = self.name or function.__name__

        @functools.wraps(function)
        async def _async_wrapper(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
            logger.debug(f"{_name} called")
            (_metadata, start) = _initial_info(args, self.metadata)
            await plugin.before_invocation(name=_name, metadata=_metadata)
            try:
                value = await function(*args, **kwargs)
                logger.debug(f"{_name} succeeded")
                await plugin.after_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    metadata=_metadata,
                )
                return value
            except CancelledError as ex:
                logger.debug(f"{_name} cancelled")
                _metadata["cancelled"] = True
                await plugin.after_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    metadata=_metadata,
                )
                raise ex
            except Exception as ex:
                logger.debug(f"{_name} failed")
                await plugin.failed_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    exception=ex,
                    metadata=_metadata,
                )
                raise ex

        @functools.wraps(function)
        async def _async_gen_wrapper(*args, **kwargs) -> Any:  # pyre-ignore
            logger.debug(f"{_name} started")
            (_metadata, start) = _initial_info(args, self.metadata)
            await plugin.before_invocation(name=_name, metadata=_metadata)
            try:
                async for value in function(*args, **kwargs):
                    yield value
                logger.debug(f"{_name} finished")
                await plugin.after_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    metadata=_metadata,
                )
            except CancelledError as ex:
                logger.debug(f"{_name} cancelled")
                _metadata["cancelled"] = True
                await plugin.after_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    metadata=_metadata,
                )
                raise ex
            except Exception as ex:
                logger.debug(f"{_name} failed")
                await plugin.failed_invocation(
                    name=_name,
                    duration=int((time.time() - start) * 1000),
                    exception=ex,
                    metadata=_metadata,
                )
                raise ex

        if inspect.isasyncgenfunction(function):
            return _async_gen_wrapper
        else:
            return _async_wrapper
