#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import importlib
import logging
import os
from argparse import ArgumentParser
from functools import wraps
from logging import Logger
from types import ModuleType
from typing import Dict, List

from idb.common.command import Command
from idb.common.types import LoggingMetadata


def package_exists(package_name: str) -> bool:
    try:
        return importlib.util.find_spec(package_name) is not None
    except Exception:
        return False


PLUGIN_PACKAGE_NAMES = ["idb.fb.plugin"]
PLUGINS: List[ModuleType] = [
    importlib.import_module(package.name)
    for package in [
        importlib.util.find_spec(package_name)
        for package_name in PLUGIN_PACKAGE_NAMES
        if package_exists(package_name)
    ]
    if package is not None
]
_META_ENVIRON_PREFIX = "IDB_META_"
logger: logging.Logger = logging.getLogger(__name__)


# pyre-ignore
def swallow_exceptions(f):
    if asyncio.iscoroutinefunction(f):

        @wraps(f)
        async def inner(*args, **kwargs) -> None:
            try:
                return await f(*args, **kwargs)
            except Exception:
                logger.exception(f"{f.__name__} plugin failed, swallowing exception")

    else:

        @wraps(f)
        def inner(*args, **kwargs) -> None:  # pyre-ignore
            try:
                return f(*args, **kwargs)
            except Exception:
                logger.exception(f"{f.__name__} plugin failed, swallowing exception")

    return inner


@swallow_exceptions
def on_launch(logger: Logger) -> None:
    for plugin in PLUGINS:
        on_launch = getattr(plugin, "on_launch", None)
        if on_launch is None:
            continue
        on_launch(logger)


@swallow_exceptions
async def on_close(logger: Logger) -> None:
    await asyncio.gather(
        *[
            plugin.on_close(logger)  # pyre-ignore
            for plugin in PLUGINS
            if hasattr(plugin, "on_close")
        ],
    )


@swallow_exceptions
async def before_invocation(name: str, metadata: LoggingMetadata) -> None:
    await asyncio.gather(
        *[
            plugin.before_invocation(name=name, metadata=metadata)  # pyre-ignore
            for plugin in PLUGINS
            if hasattr(plugin, "before_invocation")
        ]
    )


@swallow_exceptions
async def after_invocation(name: str, duration: int, metadata: LoggingMetadata) -> None:
    await asyncio.gather(
        *[
            plugin.after_invocation(  # pyre-ignore
                name=name, duration=duration, metadata=metadata
            )
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
            plugin.failed_invocation(  # pyre-ignore
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
        plugin_parser(parser=parser, logger=logger)


def resolve_metadata(logger: Logger) -> LoggingMetadata:
    metadata: LoggingMetadata = {
        key[len(_META_ENVIRON_PREFIX) :]: value
        for (key, value) in os.environ.items()
        if key.startswith(_META_ENVIRON_PREFIX)
    }
    for plugin in PLUGINS:
        plugin_resolver = getattr(plugin, "resolve_metadata", None)
        if not plugin_resolver:
            continue
        resolved = plugin_resolver(logger=logger)
        metadata.update(resolved)
    return metadata


def append_companion_metadata(
    logger: Logger, metadata: Dict[str, str]
) -> LoggingMetadata:
    for plugin in PLUGINS:
        method = getattr(plugin, "append_companion_metadata", None)
        if not method:
            continue
        metadata = method(logger=logger, metadata=metadata)
    return metadata


def get_commands() -> List[Command]:
    commands = []

    for plugin in PLUGINS:
        method = getattr(plugin, "get_commands", None)
        if not method:
            continue
        commands.extend(method())

    return commands
