#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import concurrent.futures
import logging
import os
import sys
import warnings
from typing import Union

# Suppress thrift-py-deprecated migration warnings from internal Meta libraries.
# These are emitted by libfb.py.asyncio.scribe (used for scuba logging) and are
# not actionable by idb users. The migration is tracked in the owning library.
warnings.filterwarnings(
    "ignore",
    message="Uses thrift-py-deprecated",
    module=r"libfb\.py\..*",
)

# Mute infrastructure loggers that would otherwise leak to stderr on every
# idb invocation. Users only care about idb output, not scuba teardown noise.
logging.getLogger("scuba_logger").setLevel(logging.CRITICAL)

import idb.common.plugin as plugin
from idb.cli.command_tree import build_command_graph, get_default_companion_path
from idb.cli.commands.target import ConnectCommandException
from idb.common.command import Command
from idb.common.types import IdbException


__all__ = [
    "drain_coroutines",
    "gen_main",
    "get_default_companion_path",
    "main",
    "main_2",
]

COROUTINE_DRAIN_TIMEOUT = 2


# Set the logger's basicConfig first, then add the logview handlers
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] - %(name)s - %(message)s"
)
logger: logging.Logger = logging.getLogger()


SysExitArg = Union[int, str, None]


def load_runtime_extension_commands() -> list[Command]:
    plugin.load_cli_plugins()
    return plugin.get_commands()


async def gen_main(cmd_input: list[str] | None = None) -> SysExitArg:
    # Make sure all files are created with global rw permissions
    os.umask(0o000)
    # Setup parser
    graph = build_command_graph(extension_loader=load_runtime_extension_commands)
    parser = graph.parser
    root_command = graph.root_command

    # Parse input and run
    cmd_input = cmd_input or sys.argv[1:]

    try:
        args = parser.parse_args(cmd_input)
        plugin.on_launch(logger, subcommands=root_command.resolve_subcommand_path(args))
        await root_command.run(args)
        return 0
    except ConnectCommandException as e:
        print(str(e), file=sys.stderr)
        return 1
    except IdbException as e:
        print(e.args[0], file=sys.stderr)
        return 1
    except SystemExit as e:
        return e.code
    except Exception:
        logger.exception("Exception thrown in main")
        return 1
    finally:
        await plugin.on_close(logger)
        pending = set(asyncio.all_tasks())
        current_task = asyncio.current_task()
        if current_task is not None:
            pending.discard(current_task)
        await drain_coroutines(pending)


async def drain_coroutines(pending: set[asyncio.Task]) -> None:
    if not pending:
        return
    logger.debug(f"Shutting down {len(pending)} coroutines")
    try:
        await asyncio.wait_for(
            asyncio.shield(asyncio.gather(*pending)), timeout=COROUTINE_DRAIN_TIMEOUT
        )
        logger.debug("Drained all coroutines")
    except asyncio.TimeoutError:
        logger.debug("Timeout waiting for coroutines to drain")
    except concurrent.futures.CancelledError:
        pass


def main(cmd_input: list[str] | None = None) -> SysExitArg:
    return asyncio.run(gen_main(cmd_input))


def main_2() -> None:
    sys.exit(main())


if __name__ == "__main__":
    main_2()
