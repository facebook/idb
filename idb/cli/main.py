#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import argparse
import asyncio
import concurrent.futures
import logging
import os
import sys
from typing import List, Optional, Set

import idb.common.plugin as plugin
from idb.cli.commands.accessibility import (
    AccessibilityInfoAllCommand,
    AccessibilityInfoAtPointCommand,
)
from idb.cli.commands.app import (
    AppInstallCommand,
    AppListCommand,
    AppTerminateCommand,
    AppUninstallCommand,
)
from idb.cli.commands.approve import ApproveCommand
from idb.cli.commands.contacts import ContactsUpdateCommand
from idb.cli.commands.crash import (
    CrashDeleteCommand,
    CrashListCommand,
    CrashShowCommand,
)
from idb.cli.commands.daemon import DaemonCommand
from idb.cli.commands.debugserver import (
    DebugServerStartCommand,
    DebugServerStatusCommand,
    DebugServerStopCommand,
)
from idb.cli.commands.dsym import DsymInstallCommand
from idb.cli.commands.dylib import DylibInstallCommand
from idb.cli.commands.file import (
    DeprecatedPullCommand,
    DeprecatedPushCommand,
    FSListCommand,
    FSMkdirCommand,
    FSMoveCommand,
    FSPullCommand,
    FSPushCommand,
    FSRemoveCommand,
)
from idb.cli.commands.focus import FocusCommand
from idb.cli.commands.framework import FrameworkInstallCommand
from idb.cli.commands.hid import (
    ButtonCommand,
    KeyCommand,
    KeySequenceCommand,
    SwipeCommand,
    TapCommand,
    TextCommand,
)
from idb.cli.commands.instruments import InstrumentsCommand
from idb.cli.commands.keychain import KeychainClearCommand
from idb.cli.commands.kill import KillCommand
from idb.cli.commands.launch import LaunchCommand
from idb.cli.commands.location import LocationSetCommand
from idb.cli.commands.log import CompanionLogCommand, LogCommand
from idb.cli.commands.media import MediaAddCommand
from idb.cli.commands.record import RecordVideoCommand
from idb.cli.commands.screenshot import ScreenshotCommand
from idb.cli.commands.target import (
    ConnectCommandException,
    TargetBootCommand,
    TargetCloneCommand,
    TargetConnectCommand,
    TargetCreateCommand,
    TargetDeleteAllCommand,
    TargetDeleteCommand,
    TargetDescribeCommand,
    TargetDisconnectCommand,
    TargetEraseCommand,
    TargetListCommand,
    TargetShutdownCommand,
)
from idb.cli.commands.url import UrlOpenCommand
from idb.cli.commands.xctest import (
    XctestInstallCommand,
    XctestListTestsCommand,
    XctestRunCommand,
    XctestsListBundlesCommand,
)
from idb.common.command import Command, CommandGroup
from idb.common.types import IdbException


COROUTINE_DRAIN_TIMEOUT = 2


# Set the logger's basicConfig first, then add the logview handlers
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s [%(levelname)s] - %(name)s - %(message)s"
)
logger: logging.Logger = logging.getLogger()


async def gen_main(cmd_input: Optional[List[str]] = None) -> int:
    # Make sure all files are created with global rw permissions
    os.umask(0o000)
    # Setup parser
    parser = argparse.ArgumentParser(
        description="idb: a versatile tool to communicate with iOS Simulators and Devices",
        epilog="See Also: https://www.fbidb.io/docs/guided-tour",
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "--log",
        dest="log_level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        default="WARNING",
        help="Set the logging level",
    )
    parser.add_argument(
        "--companion",
        type=str,
        default=os.environ.get("IDB_COMPANION"),
        help="A string of the form HOSTNAME:PORT that will describe the companion connect to."
        "Can also be set with the IDB_COMPANION environment variable",
    )
    parser.add_argument(
        "--companion-path",
        type=str,
        default="/usr/local/bin/idb_companion" if sys.platform == "darwin" else None,
        help="The path to the idb companion binary. This is only valid when running on macOS platforms",
    )
    parser.add_argument(
        "--companion-local",
        action="store_true",
        default=bool(os.environ.get("IDB_COMPANION_LOCAL")),
        help="If set, any companion provided via IDB_COMPANION or --companion will be assumed to be running on this host."
        "Even if the companion provided is 'localhost' idb will still assume it is remote."
        "The reason for this is that idb shouldn't assume there are no tunnels from localhost to a remote host."
        "Can also be set with the IDB_COMPANION_LOCAL environment variable",
    )
    parser.add_argument(
        "--no-prune-dead-companion",
        dest="prune_dead_companion",
        action="store_false",
        default=True,
        help="If flagged will not modify local state when a companion is known to be unresponsive",
    )
    commands: List[Command] = [
        AppInstallCommand(),
        AppUninstallCommand(),
        AppListCommand(),
        LaunchCommand(),
        AppTerminateCommand(),
        CommandGroup(
            name="xctest",
            description="Operations with xctest on target",
            commands=[
                XctestInstallCommand(),
                XctestsListBundlesCommand(),
                XctestListTestsCommand(),
                XctestRunCommand(),
            ],
        ),
        CommandGroup(
            name="file",
            description="File operations on target",
            commands=[
                FSMoveCommand(),
                FSPullCommand(),
                FSPushCommand(),
                FSMkdirCommand(),
                FSRemoveCommand(),
                FSListCommand(),
            ],
        ),
        CommandGroup(
            name="contacts",
            description="Contacts database operations on target",
            commands=[ContactsUpdateCommand()],
        ),
        LogCommand(),
        CommandGroup(
            name="record",
            description="Record what the screen is doing",
            commands=[RecordVideoCommand()],
        ),
        RecordVideoCommand(),
        DeprecatedPushCommand(),
        DeprecatedPullCommand(),
        UrlOpenCommand(),
        KeychainClearCommand(),
        LocationSetCommand(),
        ApproveCommand(),
        TargetConnectCommand(),
        TargetDisconnectCommand(),
        TargetListCommand(),
        TargetDescribeCommand(),
        TargetCreateCommand(),
        TargetBootCommand(),
        TargetShutdownCommand(),
        TargetEraseCommand(),
        TargetCloneCommand(),
        TargetDeleteCommand(),
        TargetDeleteAllCommand(),
        DaemonCommand(),
        ScreenshotCommand(),
        CommandGroup(
            name="ui",
            description="UI interactions on target",
            commands=[
                AccessibilityInfoAllCommand(),
                AccessibilityInfoAtPointCommand(),
                TapCommand(),
                ButtonCommand(),
                TextCommand(),
                KeyCommand(),
                KeySequenceCommand(),
                SwipeCommand(),
            ],
        ),
        CommandGroup(
            name="crash",
            description="Operations on crashes",
            commands=[CrashListCommand(), CrashShowCommand(), CrashDeleteCommand()],
        ),
        InstrumentsCommand(),
        KillCommand(),
        MediaAddCommand(),
        FocusCommand(),
        CommandGroup(
            name="debugserver",
            description="debugserver interactions",
            commands=[
                DebugServerStartCommand(),
                DebugServerStopCommand(),
                DebugServerStatusCommand(),
            ],
        ),
        CommandGroup(
            name="dsym", description="dsym commands", commands=[DsymInstallCommand()]
        ),
        CommandGroup(
            name="dylib", description="dylib commands", commands=[DylibInstallCommand()]
        ),
        CommandGroup(
            name="framework",
            description="framework commands",
            commands=[FrameworkInstallCommand()],
        ),
        CommandGroup(
            name="companion",
            description="commands related to the companion",
            commands=[CompanionLogCommand()],
        ),
    ]
    commands.extend(plugin.get_commands())
    root_command = CommandGroup(
        name="root_command",
        description="",
        commands=sorted(commands, key=lambda command: command.name),
    )
    root_command.add_parser_arguments(parser)

    # Parse input and run
    cmd_input = cmd_input or sys.argv[1:]

    try:
        args = parser.parse_args(cmd_input)
        plugin.on_launch(logger)
        await root_command.run(args)
        return 0
    except ConnectCommandException as e:
        print(str(e), file=sys.stderr)
        return 1
    except IdbException as e:
        print(e.args[0], file=sys.stderr)
        return 1
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


async def drain_coroutines(pending: Set[asyncio.Task]) -> None:
    if not pending:
        return
    logger.debug(f"Shutting down {len(pending)} coroutines")
    try:
        await asyncio.wait_for(
            asyncio.shield(asyncio.gather(*pending)), timeout=COROUTINE_DRAIN_TIMEOUT
        )
        logger.debug(f"Drained all coroutines")
    except asyncio.TimeoutError:
        logger.debug(f"Timeout waiting for coroutines to drain")
    except concurrent.futures.CancelledError:
        pass


def main(cmd_input: Optional[List[str]] = None) -> int:
    loop = asyncio.get_event_loop()
    try:
        return loop.run_until_complete(gen_main(cmd_input))
    finally:
        loop.close()


if __name__ == "__main__":
    sys.exit(main())
