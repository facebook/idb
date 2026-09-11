#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Characterization tests for the built-in command graph.

These record the graph as it is, not as anyone would design it: the point is
that extracting graph construction from process startup changed nothing an
invocation can observe.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import shutil
import sys
import unittest
from argparse import ArgumentParser, Namespace
from unittest import mock

from idb.cli.command_tree import (
    build_command_graph,
    BUNDLED_COMPANION_PATH,
    COMPANION_BINARY_NAME,
    CONVENTIONAL_COMPANION_PATH,
    DESCRIPTION,
    EPILOG,
    get_default_companion_path,
    ROOT_COMMAND_NAME,
)
from idb.cli.commands.shell import ShellCommand
from idb.common.command import Command, CommandGroup, CompositeCommand


BUILT_IN_ROOT_ENTRIES: tuple[str, ...] = (
    "add-media",
    "approve",
    "boot",
    "clear-keychain",
    "clone",
    "companion",
    "connect",
    "contacts",
    "crash",
    "create",
    "dap",
    "debugserver",
    "delete",
    "delete-all",
    "describe",
    "disconnect",
    "dsym",
    "dylib",
    "erase",
    "file",
    "focus",
    "framework",
    "get",
    "help",
    "install",
    "instruments",
    "kill",
    "launch",
    "list",
    "list-apps",
    "list-targets",
    "log",
    "open",
    "photos",
    "record",
    "revoke",
    "screenshot",
    "send-notification",
    "set",
    "set-location",
    "shell",
    "shutdown",
    "simulate-memory-warning",
    "terminate",
    "ui",
    "uninstall",
    "video",
    "video-stream",
    "xctest",
    "xctrace",
)

BUILT_IN_GROUP_CHILDREN: dict[str, tuple[str, ...]] = {
    "companion": ("log",),
    "contacts": ("update", "clear"),
    "crash": ("list", "show", "delete"),
    "debugserver": ("start", "stop", "status"),
    "dsym": ("install",),
    "dylib": ("install",),
    "file": (
        "move",
        "pull",
        "push",
        "mkdir",
        "remove",
        "list",
        "read",
        "write",
        "tail",
    ),
    "framework": ("install",),
    "list": ("locale",),
    "photos": ("clear",),
    "record": ("video",),
    "ui": (
        "describe-all",
        "describe-point",
        "describe",
        "scroll",
        "set-value",
        "drag-and-drop",
        "tap",
        "multi-tap",
        "pinch",
        "button",
        "remote",
        "text",
        "key",
        "key-sequence",
        "swipe",
        "rotate",
        "shake",
    ),
    "xctest": ("install", "list", "list-bundle", "run"),
    "xctrace": ("record",),
}

BUILT_IN_TERMINAL_COUNT = 84
BUILT_IN_NODE_COUNT = 99

BUILT_IN_ALIAS_PATHS: tuple[tuple[str, ...], ...] = (
    ("file", "mv"),
    ("file", "rm"),
    ("file", "ls"),
    ("file", "show"),
    ("record", "record-video"),
    ("record-video",),
)


class _ExtensionCommand(Command):
    """Stands in for a command a runtime extension contributes."""

    @property
    def name(self) -> str:
        return "aaa-extension"

    @property
    def description(self) -> str:
        return "Contributed at runtime"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("--extension-only", action="store_true", default=False)

    async def run(self, args: Namespace) -> None:
        raise AssertionError("the graph never runs a command")


def _tracking_parser_class(
    created: list[argparse.ArgumentParser],
) -> type[argparse.ArgumentParser]:
    class _TrackingParser(argparse.ArgumentParser):
        def __init__(self, *args: object, **kwargs: object) -> None:
            # pyre-ignore[6]: argparse's own signature is passed through.
            super().__init__(*args, **kwargs)
            created.append(self)

    return _TrackingParser


def _renaming_parser_class(prog: str) -> type[argparse.ArgumentParser]:
    """A parser class that stamps its own program name on every parser.

    argparse propagates the class to every sub-parser and derives a
    sub-parser's ``prog`` from its parent's, so a graph built with this class
    is identifiable in any help or usage text it produces - which is how a
    graph that reached into another one is caught by behaviour rather than by
    object identity.
    """

    class _RenamedParser(argparse.ArgumentParser):
        def __init__(self, *args: object, **kwargs: object) -> None:
            kwargs["prog"] = prog
            # pyre-ignore[6]: argparse's own signature is passed through.
            super().__init__(*args, **kwargs)

    return _RenamedParser


def _resolve(root: CompositeCommand, path: tuple[str, ...]) -> Command:
    """The command at ``path``, by walking the tree from ``root``."""
    command: Command = root
    for name in path:
        assert isinstance(command, CompositeCommand), path
        command = command.subcommands_by_name[name]
    return command


def _group(root: CompositeCommand, path: tuple[str, ...]) -> CompositeCommand:
    command = _resolve(root, path)
    assert isinstance(command, CompositeCommand), path
    return command


def _commands_by_path(
    command: Command, prefix: tuple[str, ...]
) -> dict[tuple[str, ...], Command]:
    here: tuple[str, ...] = prefix + (command.name,)
    found: dict[tuple[str, ...], Command] = {here: command}
    if isinstance(command, CompositeCommand):
        for child in command.subcommands:
            found.update(_commands_by_path(child, here))
    return found


def _nodes(command: Command, prefix: tuple[str, ...]) -> list[tuple[str, ...]]:
    here: tuple[str, ...] = prefix + (command.name,)
    nodes: list[tuple[str, ...]] = [here]
    if isinstance(command, CompositeCommand):
        for child in command.subcommands:
            nodes.extend(_nodes(child, here))
    return nodes


def _alias_paths(command: Command, prefix: tuple[str, ...]) -> list[tuple[str, ...]]:
    paths: list[tuple[str, ...]] = [prefix + (alias,) for alias in command.aliases]
    if isinstance(command, CompositeCommand):
        here: tuple[str, ...] = prefix + (command.name,)
        for child in command.subcommands:
            paths.extend(_alias_paths(child, here))
    return paths


class CommandTreeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.maxDiff = None
        self.graph = build_command_graph()

    def test_root_entries(self) -> None:
        self.assertEqual(
            tuple(command.name for command in self.graph.root_command.subcommands),
            BUILT_IN_ROOT_ENTRIES,
        )

    def test_group_children(self) -> None:
        children = {
            command.name: tuple(child.name for child in command.subcommands)
            for command in self.graph.root_command.subcommands
            if isinstance(command, CompositeCommand)
        }
        self.assertEqual(children, BUILT_IN_GROUP_CHILDREN)

    def test_node_and_terminal_counts(self) -> None:
        nodes = [
            path
            for command in self.graph.root_command.subcommands
            for path in _nodes(command, ())
        ]
        self.assertEqual(len(nodes), BUILT_IN_NODE_COUNT)
        self.assertEqual(len(set(nodes)), BUILT_IN_NODE_COUNT)

    def test_terminal_count(self) -> None:
        def terminals(command: Command, prefix: tuple[str, ...]) -> int:
            if not isinstance(command, CompositeCommand):
                return 1
            return sum(
                terminals(child, prefix + (command.name,))
                for child in command.subcommands
            )

        self.assertEqual(
            sum(
                terminals(command, ())
                for command in self.graph.root_command.subcommands
            ),
            BUILT_IN_TERMINAL_COUNT,
        )

    def test_alias_paths(self) -> None:
        paths = [
            path
            for command in self.graph.root_command.subcommands
            for path in _alias_paths(command, ())
        ]
        self.assertEqual(tuple(paths), BUILT_IN_ALIAS_PATHS)

    def test_root_parser_presentation(self) -> None:
        parser = self.graph.parser
        self.assertEqual(parser.prog, "idb")
        self.assertEqual(parser.description, DESCRIPTION)
        self.assertEqual(parser.epilog, EPILOG)
        self.assertIs(parser.formatter_class, argparse.RawTextHelpFormatter)
        self.assertEqual(self.graph.root_command.name, ROOT_COMMAND_NAME)

    def test_root_arguments(self) -> None:
        args = self.graph.parser.parse_args(["list-targets"])
        self.assertEqual(args.log_level, "WARNING")
        self.assertIsNone(args.compression)
        self.assertEqual(args.companion_path, get_default_companion_path())
        self.assertTrue(args.prune_dead_companion)
        self.assertFalse(args.companion_tls)

    def test_root_options_precede_the_command(self) -> None:
        args = self.graph.parser.parse_args(["--log", "DEBUG", "list-targets"])
        self.assertEqual(args.log_level, "DEBUG")
        self.assertEqual(args.root_command, "list-targets")

    def test_alias_resolves_to_its_canonical_path(self) -> None:
        args = self.graph.parser.parse_args(["file", "ls", "/", "--bundle-id", "com.x"])
        self.assertEqual(
            self.graph.root_command.resolve_subcommand_path(args), ["file", "list"]
        )

    def test_shell_command_is_wired_to_the_graph(self) -> None:
        shell = self.graph.root_command.subcommands_by_name["shell"]
        self.assertIsInstance(shell, ShellCommand)
        assert isinstance(shell, ShellCommand)
        self.assertIs(shell.root_command, self.graph.root_command)
        self.assertIs(shell.parser, self.graph.parser)

    # The two seams the extraction exists for.

    def test_no_extension_loader_yields_only_built_in_commands(self) -> None:
        self.assertNotIn(
            "aaa-extension",
            [command.name for command in self.graph.root_command.subcommands],
        )

    def test_extension_commands_are_loaded_and_sorted_in(self) -> None:
        graph = build_command_graph(extension_loader=lambda: [_ExtensionCommand()])
        names = [command.name for command in graph.root_command.subcommands]
        self.assertEqual(names[0], "aaa-extension")
        self.assertEqual(len(names), len(BUILT_IN_ROOT_ENTRIES) + 1)
        self.assertEqual(tuple(names[1:]), BUILT_IN_ROOT_ENTRIES)
        args = graph.parser.parse_args(["aaa-extension", "--extension-only"])
        self.assertTrue(args.extension_only)

    def test_extension_loader_is_called_once(self) -> None:
        calls = []

        def loader() -> list[Command]:
            calls.append(None)
            return []

        build_command_graph(extension_loader=loader)
        self.assertEqual(len(calls), 1)

    def test_parser_class_is_used_for_every_parser(self) -> None:
        created: list[argparse.ArgumentParser] = []
        parser_class = _tracking_parser_class(created)
        graph = build_command_graph(parser_class=parser_class)
        self.assertIsInstance(graph.parser, parser_class)
        self.assertEqual(len(created), BUILT_IN_NODE_COUNT + 1)
        for parser in created:
            self.assertIsInstance(parser, parser_class)

    def test_graphs_are_independent(self) -> None:
        other = build_command_graph()
        self.assertIsNot(self.graph.parser, other.parser)
        self.assertIsNot(self.graph.root_command, other.root_command)
        self.assertEqual(
            [command.name for command in self.graph.root_command.subcommands],
            [command.name for command in other.root_command.subcommands],
        )

    # Independence has to hold all the way down. A command is mutable - a
    # group records the parser it was added to and memoises its subcommand
    # lookup - so a nested command shared between two graphs lets the second
    # graph's construction reach back into the first.

    def test_no_command_object_is_shared_between_graphs(self) -> None:
        other = build_command_graph()
        mine = _commands_by_path(self.graph.root_command, ())
        theirs = _commands_by_path(other.root_command, ())
        self.assertEqual(sorted(mine), sorted(theirs))
        shared = sorted(path for path in mine if mine[path] is theirs[path])
        self.assertEqual(shared, [])

    def test_nested_groups_are_distinct_between_graphs(self) -> None:
        other = build_command_graph()
        for path in ((ROOT_COMMAND_NAME, "xctest", "run"), (ROOT_COMMAND_NAME, "list")):
            with self.subTest(path=path):
                mine = _group(self.graph.root_command, path[1:])
                theirs = _group(other.root_command, path[1:])
                self.assertIsNot(mine, theirs)
                self.assertIsNot(mine.parser, theirs.parser)
                self.assertEqual(
                    [child.name for child in mine.subcommands],
                    [child.name for child in theirs.subcommands],
                )

    def test_building_a_graph_leaves_an_earlier_graphs_parsers_bound(self) -> None:
        nested = _group(self.graph.root_command, ("xctest", "run"))
        before = nested.parser
        self.assertIsNotNone(before)
        created: list[argparse.ArgumentParser] = []
        build_command_graph(parser_class=_tracking_parser_class(created))
        self.assertIs(nested.parser, before)
        self.assertNotIn(nested.parser, created)

    def test_a_later_graph_cannot_change_an_earlier_graphs_nested_help(self) -> None:
        nested = _group(self.graph.root_command, ("xctest", "run"))
        parser = nested.parser
        assert parser is not None
        before = parser.format_help()
        build_command_graph(parser_class=_renaming_parser_class("idb-second"))
        after = nested.parser
        assert after is not None
        self.assertEqual(after.format_help(), before)
        self.assertNotIn("idb-second", before)
        self.assertNotIn("idb-second", after.format_help())

    def test_a_later_graph_cannot_change_an_earlier_graphs_group_error(self) -> None:
        # A group with no sub-command chosen prints the help of whichever
        # parser it last recorded, so this is the shared state made audible.
        build_command_graph(parser_class=_renaming_parser_class("idb-second"))
        args = self.graph.parser.parse_args(["xctest", "run"])
        out, err = io.StringIO(), io.StringIO()
        with (
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(err),
            self.assertRaises(SystemExit),
        ):
            self.graph.root_command.resolve_command_from_args(args)
        printed = out.getvalue() + err.getvalue()
        self.assertIn("run", printed)
        self.assertNotIn("idb-second", printed)

    def test_a_later_graph_cannot_change_an_earlier_graphs_resolution(self) -> None:
        other = build_command_graph()
        args = self.graph.parser.parse_args(
            ["xctest", "run", "logic", "com.example.tests"]
        )
        resolved = self.graph.root_command.resolve_command_from_args(args)
        path = ("xctest", "run", "logic")
        self.assertIs(resolved, _resolve(self.graph.root_command, path))
        self.assertIsNot(resolved, _resolve(other.root_command, path))
        self.assertEqual(
            self.graph.root_command.resolve_subcommand_path(args), list(path)
        )

    def test_a_module_level_group_is_never_the_one_in_the_graph(self) -> None:
        # The exported globals stay for callers that already import them, but
        # nothing in a graph may be one of them.
        from idb.cli.commands.settings import ListCommand
        from idb.cli.commands.xctest import XctestRunCommand

        for exported in (ListCommand, XctestRunCommand):
            with self.subTest(exported=exported.name):
                self.assertIsInstance(exported, CommandGroup)
                self.assertIsNone(exported.parser)
                for command in _commands_by_path(self.graph.root_command, ()).values():
                    self.assertIsNot(command, exported)

    def test_the_tenth_graph_has_the_same_shape_as_the_first(self) -> None:
        first = sorted(_commands_by_path(self.graph.root_command, ()))
        for _ in range(9):
            latest = build_command_graph()
            self.assertEqual(sorted(_commands_by_path(latest.root_command, ())), first)


class DefaultCompanionPathTest(unittest.TestCase):
    """The parser default that probes the host platform.

    The graph records the probe as the source of the default rather than
    embedding a host-specific path, so the probe's outcomes are tested here.
    """

    def _companion_path(
        self, *, platform: str, bundled: bool, on_path: str | None
    ) -> str | None:
        with (
            mock.patch.object(sys, "platform", platform),
            mock.patch.object(
                os.path,
                "isfile",
                lambda path: bundled and path == BUNDLED_COMPANION_PATH,
            ),
            mock.patch.object(
                shutil,
                "which",
                lambda name: on_path if name == COMPANION_BINARY_NAME else None,
            ),
        ):
            return get_default_companion_path()

    def test_a_bundled_companion_wins_over_one_on_the_path(self) -> None:
        self.assertEqual(
            self._companion_path(
                platform="darwin",
                bundled=True,
                on_path="/opt/homebrew/bin/idb_companion",
            ),
            BUNDLED_COMPANION_PATH,
        )

    def test_without_a_bundled_companion_the_path_decides(self) -> None:
        self.assertEqual(
            self._companion_path(
                platform="darwin",
                bundled=False,
                on_path="/opt/homebrew/bin/idb_companion",
            ),
            "/opt/homebrew/bin/idb_companion",
        )

    def test_with_nothing_found_the_conventional_location_is_assumed(self) -> None:
        self.assertEqual(
            self._companion_path(platform="darwin", bundled=False, on_path=None),
            CONVENTIONAL_COMPANION_PATH,
        )

    def test_off_darwin_there_is_no_default_and_nothing_is_probed(self) -> None:
        for platform in ("linux", "win32"):
            with self.subTest(platform=platform):
                self.assertIsNone(
                    self._companion_path(
                        platform=platform,
                        bundled=True,
                        on_path="/anywhere/idb_companion",
                    )
                )

    @unittest.skipUnless(sys.platform == "darwin", "records the real macOS outcome")
    def test_on_a_real_mac_the_default_names_a_companion(self) -> None:
        path = get_default_companion_path()
        self.assertIsNotNone(path)
        assert path is not None
        self.assertTrue(path.endswith(COMPANION_BINARY_NAME), path)
        self.assertTrue(os.path.isabs(path), path)

    @unittest.skipIf(sys.platform == "darwin", "records the real non-macOS outcome")
    def test_off_a_real_mac_there_is_no_default(self) -> None:
        self.assertIsNone(get_default_companion_path())
