#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from __future__ import annotations

import asyncio
import importlib
import logging
import os
import ssl
from argparse import ArgumentParser, Namespace
from collections.abc import Awaitable, Callable, Iterator
from contextlib import contextmanager
from contextvars import ContextVar
from functools import wraps
from logging import Logger
from types import ModuleType
from typing import cast, List, overload, ParamSpec, TypeVar

from idb.common.command import Command
from idb.common.types import IdbException, LoggingMetadata


def package_exists(package_name: str) -> bool:
    try:
        return importlib.util.find_spec(package_name) is not None
    except Exception:
        return False


PLUGIN_PACKAGE_NAMES = ["idb.fb.plugin"]
CLI_PLUGIN_PACKAGE_NAMES = ["idb.fb.cli_plugin"]


def _load_plugins(package_names: list[str]) -> list[ModuleType]:
    return [
        importlib.import_module(package.name)
        for package in [
            importlib.util.find_spec(package_name)
            for package_name in package_names
            if package_exists(package_name)
        ]
        if package is not None
    ]


PLUGINS: list[ModuleType] = _load_plugins(PLUGIN_PACKAGE_NAMES)
_META_ENVIRON_PREFIX = "IDB_META_"
logger: logging.Logger = logging.getLogger(__name__)
_SCOPED_METADATA: ContextVar[LoggingMetadata | None] = ContextVar(
    "idb_scoped_invocation_metadata",
    default=None,
)


@contextmanager
def scoped_invocation_metadata(metadata: LoggingMetadata) -> Iterator[None]:
    current = _SCOPED_METADATA.get() or {}
    token = _SCOPED_METADATA.set({**current, **metadata})
    try:
        yield
    finally:
        _SCOPED_METADATA.reset(token)


def current_scoped_invocation_metadata() -> LoggingMetadata:
    return dict(_SCOPED_METADATA.get() or {})


def load_cli_plugins() -> None:
    loaded_names = {plugin.__name__ for plugin in PLUGINS}
    PLUGINS.extend(
        plugin
        for plugin in _load_plugins(CLI_PLUGIN_PACKAGE_NAMES)
        if plugin.__name__ not in loaded_names
    )


P = ParamSpec("P")
T = TypeVar("T")


@overload
def swallow_exceptions(
    f: Callable[P, Awaitable[T]],
) -> Callable[P, Awaitable[T | None]]: ...


@overload
def swallow_exceptions(f: Callable[P, T]) -> Callable[P, T | None]: ...


def swallow_exceptions(
    f: Callable[P, T] | Callable[P, Awaitable[T]],
) -> Callable[P, T | None] | Callable[P, Awaitable[T | None]]:
    if asyncio.iscoroutinefunction(f):

        @wraps(f)
        async def inner(*args: P.args, **kwargs: P.kwargs) -> T | None:
            try:
                return await f(*args, **kwargs)
            except Exception:
                logger.exception(f"{f.__name__} plugin failed, swallowing exception")

    else:
        # iscoroutinefunction does not narrow the union type of f for type
        # checkers; the else branch can only be the synchronous callable.
        sync_f = cast(Callable[P, T], f)

        @wraps(f)
        def inner(*args: P.args, **kwargs: P.kwargs) -> T | None:
            try:
                return sync_f(*args, **kwargs)
            except Exception:
                logger.exception(f"{f.__name__} plugin failed, swallowing exception")

    return inner


@swallow_exceptions
def on_launch(logger: Logger, subcommands: list[str]) -> None:
    for plugin in PLUGINS:
        on_launch = getattr(plugin, "on_launch", None)
        if on_launch is None:
            continue
        on_launch(logger, subcommands=subcommands)


@swallow_exceptions
async def on_close(logger: Logger) -> None:
    await asyncio.gather(
        *[plugin.on_close(logger) for plugin in PLUGINS if hasattr(plugin, "on_close")],
    )


@swallow_exceptions
async def before_invocation(name: str, metadata: LoggingMetadata) -> None:
    await asyncio.gather(
        *[
            plugin.before_invocation(name=name, metadata=metadata)
            for plugin in PLUGINS
            if hasattr(plugin, "before_invocation")
        ]
    )


@swallow_exceptions
async def after_invocation(name: str, duration: int, metadata: LoggingMetadata) -> None:
    await asyncio.gather(
        *[
            plugin.after_invocation(name=name, duration=duration, metadata=metadata)
            for plugin in PLUGINS
            if hasattr(plugin, "after_invocation")
        ]
    )


@swallow_exceptions
async def failed_invocation(
    name: str, duration: int, exception: BaseException, metadata: LoggingMetadata
) -> None:
    await asyncio.gather(
        *[
            plugin.failed_invocation(
                name=name, duration=duration, exception=exception, metadata=metadata
            )
            for plugin in PLUGINS
            if hasattr(plugin, "failed_invocation")
        ]
    )


@swallow_exceptions
def on_connecting_parser(parser: ArgumentParser, logger: Logger) -> None:
    for plugin in PLUGINS:
        plugin_parser = getattr(plugin, "on_connecting_parser", None)
        if parser is None:
            continue
        # pyrefly: ignore [not-callable]
        plugin_parser(parser=parser, logger=logger)


def on_command_parsed(logger: Logger, command: Command, args: Namespace) -> None:
    # A plugin rejects the command by raising IdbException; that is policy, not
    # a bug, and propagates. Any other exception is a plugin failure and stays
    # isolated per plugin so it cannot suppress later hooks or the command.
    for plugin in PLUGINS:
        method = getattr(plugin, "on_command_parsed", None)
        if not method:
            continue
        try:
            method(logger=logger, command=command, args=args)
        except IdbException:
            raise
        except Exception:
            logger.exception(
                f"on_command_parsed plugin {plugin.__name__} failed, "
                "swallowing exception"
            )


def on_invocation_result(
    name: str, result: object, metadata: LoggingMetadata
) -> LoggingMetadata:
    # Result observation is telemetry-only: it runs after the invocation has
    # already succeeded, so a plugin failure here must never alter the outcome.
    # Every exception is swallowed per plugin, and later plugins still run.
    updates: LoggingMetadata = {}
    for plugin in PLUGINS:
        method = getattr(plugin, "on_invocation_result", None)
        if not method:
            continue
        try:
            resolved = method(name=name, result=result, metadata=metadata)
        except Exception:
            logger.exception(
                f"on_invocation_result plugin {plugin.__name__} failed, "
                "swallowing exception"
            )
            continue
        if resolved:
            updates.update(resolved)
    return updates


def get_agent_instructions(names: List[str]) -> str:
    # Help output must survive a broken plugin: failures are isolated per
    # plugin, and a failed plugin contributes nothing.
    sections: List[str] = []
    for plugin in PLUGINS:
        method = getattr(plugin, "get_agent_instructions", None)
        if not method:
            continue
        try:
            section = method(names=names)
        except Exception:
            logger.exception(
                f"get_agent_instructions plugin {plugin.__name__} failed, "
                "swallowing exception"
            )
            continue
        if section:
            sections.append(section)
    return "\n".join(sections)


def resolve_metadata(
    logger: Logger,
    command: Command | None = None,
    args: Namespace | None = None,
) -> LoggingMetadata:
    metadata: LoggingMetadata = {
        key[len(_META_ENVIRON_PREFIX) :]: value
        for (key, value) in os.environ.items()
        if key.startswith(_META_ENVIRON_PREFIX)
    }
    for plugin in PLUGINS:
        plugin_resolver = getattr(plugin, "resolve_metadata", None)
        if not plugin_resolver:
            continue
        resolved = plugin_resolver(logger=logger, command=command, args=args)
        metadata.update(resolved)
    metadata.update(current_scoped_invocation_metadata())
    return metadata


def append_companion_metadata(
    logger: Logger, metadata: dict[str, str]
) -> LoggingMetadata:
    for plugin in PLUGINS:
        method = getattr(plugin, "append_companion_metadata", None)
        if not method:
            continue
        metadata = method(logger=logger, metadata=metadata)
    # pyrefly: ignore [bad-return]
    return metadata


def get_commands() -> list[Command]:
    commands = []

    for plugin in PLUGINS:
        method = getattr(plugin, "get_commands", None)
        if not method:
            continue
        commands.extend(method())

    return commands


def channel_ssl_context() -> ssl.SSLContext | None:
    for plugin in PLUGINS:
        method = getattr(plugin, "channel_ssl_context", None)
        if not method:
            continue
        return method()

    return None
