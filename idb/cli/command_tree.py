#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Construction of the idb command graph, separated from process startup.

``main`` owns the process: umask, runtime extension loading, dispatch,
exception-to-exit mapping and coroutine draining. This module owns only the
shape of the command tree, so tooling can obtain the exact parser a real
invocation would use without running a command or loading an extension.

The graph is built the same way for every caller. The two seams exist so a
caller can decide what a graph contains and what records it:

* ``extension_loader`` supplies the runtime extension commands. ``main``
  passes the plugin loader; a caller that wants only the built-in graph
  passes nothing.
* ``parser_class`` supplies the ``ArgumentParser`` implementation. argparse
  propagates it to every sub-parser, so a recording subclass observes the
  whole tree.
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from collections.abc import Callable
from dataclasses import dataclass

from idb.cli.commands.accessibility import (
    AccessibilityDescribeMarkerCommand,
    AccessibilityDragAndDropCommand,
    AccessibilityInfoAllCommand,
    AccessibilityInfoAtPointCommand,
    AccessibilityScrollCommand,
    AccessibilitySetValueCommand,
)
from idb.cli.commands.app import (
    AppInstallCommand,
    AppListCommand,
    AppTerminateCommand,
    AppUninstallCommand,
)
from idb.cli.commands.approve import ApproveCommand
from idb.cli.commands.contacts import ContactsClearCommand, ContactsUpdateCommand
from idb.cli.commands.crash import (
    CrashDeleteCommand,
    CrashListCommand,
    CrashShowCommand,
)
from idb.cli.commands.dap import DapCommand
from idb.cli.commands.debugserver import (
    DebugServerStartCommand,
    DebugServerStatusCommand,
    DebugServerStopCommand,
)
from idb.cli.commands.dsym import DsymInstallCommand
from idb.cli.commands.dylib import DylibInstallCommand
from idb.cli.commands.file import (
    FBSReadCommand,
    FSListCommand,
    FSMkdirCommand,
    FSMoveCommand,
    FSPullCommand,
    FSPushCommand,
    FSRemoveCommand,
    FSTailCommand,
    FSWriteCommand,
)
from idb.cli.commands.focus import FocusCommand
from idb.cli.commands.framework import FrameworkInstallCommand
from idb.cli.commands.help import HelpCommand
from idb.cli.commands.hid import (
    ButtonCommand,
    KeyCommand,
    KeySequenceCommand,
    MultiTapCommand,
    PinchCommand,
    RemoteCommand,
    RotateCommand,
    ShakeCommand,
    SwipeCommand,
    TextCommand,
)
from idb.cli.commands.instruments import InstrumentsCommand
from idb.cli.commands.keychain import KeychainClearCommand
from idb.cli.commands.kill import KillCommand
from idb.cli.commands.launch import LaunchCommand
from idb.cli.commands.location import LocationSetCommand
from idb.cli.commands.log import CompanionLogCommand, LogCommand
from idb.cli.commands.media import MediaAddCommand
from idb.cli.commands.memory import SimulateMemoryWarningCommand
from idb.cli.commands.notification import SendNotificationCommand
from idb.cli.commands.photos import PhotosClearCommand
from idb.cli.commands.revoke import RevokeCommand
from idb.cli.commands.screenshot import ScreenshotCommand
from idb.cli.commands.settings import (
    build_list_command,
    GetPreferenceCommand,
    SetPreferenceCommand,
)
from idb.cli.commands.shell import ShellCommand
from idb.cli.commands.tap import TapCommand
from idb.cli.commands.target import (
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
from idb.cli.commands.video import VideoRecordCommand, VideoStreamCommand
from idb.cli.commands.xctest import (
    build_xctest_run_command,
    XctestInstallCommand,
    XctestListTestsCommand,
    XctestsListBundlesCommand,
)
from idb.cli.commands.xctrace import XctraceRecordCommand
from idb.common.command import Command, CommandGroup
from idb.common.types import Compression


DESCRIPTION = "idb: a versatile tool to communicate with iOS Simulators and Devices"
EPILOG = "See Also: https://www.fbidb.io/docs/guided-tour"
ROOT_COMMAND_NAME = "root_command"

ExtensionLoader = Callable[[], list[Command]]


# Prefer the bundled binary over the conventional wrapper at
# /usr/local/bin/idb_companion, which invokes a DotSlash stub and can observe a
# different PATH inside XAR/PAR environments.
BUNDLED_COMPANION_PATH = "/opt/facebook/idb/bin/idb_companion"
COMPANION_BINARY_NAME = "idb_companion"
CONVENTIONAL_COMPANION_PATH = "/usr/local/bin/idb_companion"


def get_default_companion_path() -> str | None:
    if sys.platform != "darwin":
        return None
    if os.path.isfile(BUNDLED_COMPANION_PATH):
        return BUNDLED_COMPANION_PATH
    return shutil.which(COMPANION_BINARY_NAME) or CONVENTIONAL_COMPANION_PATH


@dataclass(frozen=True)
class CommandGraph:
    """A parser and the command tree whose arguments were added to it."""

    parser: argparse.ArgumentParser
    root_command: CommandGroup


def add_root_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--log",
        dest="log_level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        default="WARNING",
        help="Set the logging level",
    )
    parser.add_argument(
        "--compression",
        dest="compression",
        choices=[str(key) for (key, _) in Compression.__members__.items()],
        default=None,
        help="Compression algorithm, default: GZIP. "
        "Compressor should be available at this host. "
        "Decompressor should be available at the destination site (where IDB companion is hosted)",
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
        default=get_default_companion_path(),
        help="The path to the idb companion binary. This is only valid when running on macOS platforms",
    )
    parser.add_argument(
        "--companion-tls",
        action="store_true",
        default=bool(os.environ.get("IDB_COMPANION_TLS")),
        help="Will force idb client to use TLS encrypted connection to companion."
        "Can also be set with the IDB_COMPANION_TLS environment variable",
    )
    parser.add_argument(
        "--no-prune-dead-companion",
        dest="prune_dead_companion",
        action="store_false",
        default=True,
        help="If flagged will not modify local state when a companion is known to be unresponsive",
    )


def build_builtin_commands(shell_command: ShellCommand) -> list[Command]:
    """The commands this repository declares, in declaration order.

    The order is preserved because it is the order the root group sorts, and
    a sort is only stable relative to the order it is given.

    Every command and group here is constructed fresh. A command is mutable -
    a group records the parser it was added to and memoises its subcommand
    lookup - so a shared instance would let one graph's construction reach
    back into an already-built one.
    """
    return [
        HelpCommand(),
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
                build_xctest_run_command(),
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
                FBSReadCommand(),
                FSWriteCommand(),
                FSTailCommand(),
            ],
        ),
        CommandGroup(
            name="contacts",
            description="Contacts database operations on target",
            commands=[ContactsUpdateCommand(), ContactsClearCommand()],
        ),
        CommandGroup(
            name="photos",
            description="Photos library operations on target",
            commands=[PhotosClearCommand()],
        ),
        LogCommand(),
        CommandGroup(
            name="record",
            description="Record what the screen is doing",
            commands=[VideoRecordCommand()],
        ),
        VideoRecordCommand(),
        VideoStreamCommand(),
        UrlOpenCommand(),
        KeychainClearCommand(),
        LocationSetCommand(),
        SimulateMemoryWarningCommand(),
        SendNotificationCommand(),
        ApproveCommand(),
        RevokeCommand(),
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
        ScreenshotCommand(),
        CommandGroup(
            name="ui",
            description="UI interactions on target",
            commands=[
                AccessibilityInfoAllCommand(),
                AccessibilityInfoAtPointCommand(),
                AccessibilityDescribeMarkerCommand(),
                AccessibilityScrollCommand(),
                AccessibilitySetValueCommand(),
                AccessibilityDragAndDropCommand(),
                TapCommand(),
                MultiTapCommand(),
                PinchCommand(),
                ButtonCommand(),
                RemoteCommand(),
                TextCommand(),
                KeyCommand(),
                KeySequenceCommand(),
                SwipeCommand(),
                RotateCommand(),
                ShakeCommand(),
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
        DapCommand(),
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
        CommandGroup(
            name="xctrace",
            description="Run xctrace commands",
            commands=[XctraceRecordCommand()],
        ),
        SetPreferenceCommand(),
        GetPreferenceCommand(),
        build_list_command(),
        shell_command,
    ]


def build_command_graph(
    extension_loader: ExtensionLoader | None = None,
    parser_class: type[argparse.ArgumentParser] = argparse.ArgumentParser,
) -> CommandGraph:
    """Build the parser and command tree for one idb invocation.

    Building the graph performs no I/O beyond the environment and platform
    probes the parser defaults have always performed, and runs no command.
    """
    parser = parser_class(
        description=DESCRIPTION,
        epilog=EPILOG,
        formatter_class=argparse.RawTextHelpFormatter,
    )
    add_root_arguments(parser)
    shell_command = ShellCommand(parser=parser)
    commands: list[Command] = build_builtin_commands(shell_command)
    if extension_loader is not None:
        commands.extend(extension_loader())
    root_command = CommandGroup(
        name=ROOT_COMMAND_NAME,
        description="",
        commands=sorted(commands, key=lambda command: command.name),
    )
    root_command.add_parser_arguments(parser)
    shell_command.root_command = root_command
    return CommandGraph(parser=parser, root_command=root_command)
