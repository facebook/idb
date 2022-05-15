#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
import sys
import tempfile
from abc import abstractmethod
from argparse import ArgumentParser, Namespace
from typing import List, Tuple

import aiofiles
from idb.cli import ClientCommand
from idb.common.signal import signal_handler_event
from idb.common.types import Client, Compression, FileContainer, FileContainerType


def _add_container_types_to_group(
    parser: ArgumentParser, containers: List[Tuple[FileContainerType, str]]
) -> None:
    for (container_type, help_text) in containers:
        argument_name = container_type.value.replace("_", "-")
        parser.add_argument(
            f"--{argument_name}",
            action="store_const",
            dest="container_type",
            const=container_type,
            help=help_text,
        )


class FSCommand(ClientCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        group = parser.add_mutually_exclusive_group()
        group.add_argument(
            "--bundle-id",
            help="DEPRECATED: Use --application instead. Bundle ID of application. If not provided, the 'root' of the target will be used.",
            type=str,
            required=False,
            default=None,
        )
        _add_container_types_to_group(
            group,  # pyre-fixme[6]: _MutuallyExclusiveGroup is not public.
            [
                (
                    FileContainerType.APPLICATION,
                    "Use the container of application containers. Applications containers are presented, by bundle-id in the root.",
                ),
                (
                    FileContainerType.AUXILLARY,
                    "Use the auxillary container. This is where idb will store intermediate files.",
                ),
                (
                    FileContainerType.GROUP,
                    "Use the group containers. Group containers are shared directories between applications and are prefixed with reverse-domain identifiers (e.g 'group.com.apple.safari')",
                ),
                (FileContainerType.ROOT, "Use the root file container"),
                (FileContainerType.MEDIA, "Use the media container"),
                (FileContainerType.CRASHES, "Use the crashes container"),
                (FileContainerType.DISK_IMAGES, "Use the disk images"),
                (
                    FileContainerType.PROVISIONING_PROFILES,
                    "Use the provisioning profiles container",
                ),
                (FileContainerType.MDM_PROFILES, "Use the mdm profiles container"),
                (
                    FileContainerType.SPRINGBOARD_ICONS,
                    "Use the springboard icons container",
                ),
                (FileContainerType.WALLPAPER, "Use the wallpaper container"),
                (
                    FileContainerType.XCTEST,
                    "Use the container of installed xctest bundles",
                ),
                (FileContainerType.DYLIB, "Use the container of installed dylibs"),
                (FileContainerType.DSYM, "Use the container of installed dsyms"),
                (
                    FileContainerType.FRAMEWORK,
                    "Use the container of installed frameworks",
                ),
                (
                    FileContainerType.SYMBOLS,
                    "Use the container of target-provided symbols/dyld cache",
                ),
            ],
        )
        super().add_parser_arguments(parser)

    @abstractmethod
    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        pass

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        bundle_id = args.bundle_id
        if bundle_id is not None:
            container = bundle_id
            self.logger.warn(
                f"'--bundle-id {bundle_id}' is deprecated, please use --application prefixing '{bundle_id}' in the file path/s provided to this command."
            )
        else:
            container = args.container_type
        return await self.run_with_container(
            container=container, args=args, client=client
        )


class FSListCommand(FSCommand):
    @property
    def description(self) -> str:
        return "List a path inside an application's container"

    @property
    def name(self) -> str:
        return "list"

    @property
    def aliases(self) -> List[str]:
        return ["ls"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "paths",
            help="Source path",
            nargs="+",
            default="./",
            type=str,
        )
        parser.add_argument(
            "--force-new-output",
            action="store_true",
            default=False,
            help="Force multiple-file output even if a single file is passed",
        )
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        if len(args.paths) > 1 or args.force_new_output:
            listings_by_path = await client.ls(container=container, paths=args.paths)
            if args.json:
                listings_output = {}
                for listing in listings_by_path:
                    listings_output[f"{listing.parent}"] = [
                        entry.path for entry in listing.entries
                    ]
                print(json.dumps(listings_output))
            else:
                for listing in listings_by_path:
                    print(f"{listing.parent}:")
                    for entry in listing.entries:
                        print(entry.path)
        else:
            # Handle listing of a single path (no prefixing of the directory)
            paths = await client.ls_single(container=container, path=args.paths[0])
            if args.json:
                print(json.dumps([{"path": item.path} for item in paths]))
            else:
                for item in paths:
                    print(item.path)


class FSMkdirCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Make a directory inside an application's container"

    @property
    def name(self) -> str:
        return "mkdir"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "path",
            help="Path to directory to create",
            type=str,
        )

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        await client.mkdir(container=container, path=args.path)


class FSMoveCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Move a path inside an application's container"

    @property
    def name(self) -> str:
        return "move"

    @property
    def aliases(self) -> List[str]:
        return ["mv"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "src",
            help="Source paths relative to Container",
            nargs="+",
            type=str,
        )
        parser.add_argument(
            "dst",
            help="Destination path relative to Container",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        await client.mv(container=container, src_paths=args.src, dest_path=args.dst)


class FSRemoveCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Remove an item inside a container"

    @property
    def name(self) -> str:
        return "remove"

    @property
    def aliases(self) -> List[str]:
        return ["rm"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "path",
            help="Path of item to remove (A directory will be recursively deleted)",
            nargs="+",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        await client.rm(container=container, paths=args.path)


class FSPushCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Copy file(s) from local machine to target"

    @property
    def name(self) -> str:
        return "push"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "src_paths", help="Path of file(s) to copy to the target", nargs="+"
        )
        parser.add_argument(
            "dest_path",
            help=(
                "Directory relative to the data container of the application\n"
                "to copy the files into. Will be created if non-existent"
            ),
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )
        return await client.push(
            container=container,
            src_paths=[os.path.abspath(path) for path in args.src_paths],
            dest_path=args.dest_path,
            compression=compression,
        )


class FSPullCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Copy a file inside an application's container"

    @property
    def name(self) -> str:
        return "pull"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "src",
            help="Relative Container source path",
            type=str,
        )
        parser.add_argument("dst", help="Local destination path", type=str)
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        await client.pull(
            container=container, src_path=args.src, dest_path=os.path.abspath(args.dst)
        )


class FBSReadCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Read the contents of a remote file and write it to stdout"

    @property
    def name(self) -> str:
        return "read"

    @property
    def aliases(self) -> List[str]:
        return ["show"]

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "src",
            help="Relatve Container source path",
            type=str,
        )
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        with tempfile.TemporaryDirectory() as destination_directory:
            # Remove the tempfile so that it can be written to.
            destination_directory = os.path.abspath(destination_directory)
            destination_file = os.path.join(
                destination_directory, os.path.basename(args.src)
            )
            await client.pull(
                container=container, src_path=args.src, dest_path=destination_directory
            )
            async with aiofiles.open(destination_file, "rb") as f:
                data = await f.read()
                sys.stdout.buffer.write(data)


class FSWriteCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Read stdin and write it to a remote file"

    @property
    def name(self) -> str:
        return "write"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("dst", help="Relatve container destination path", type=str)
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        data = sys.stdin.buffer.read()
        (destination_directory, destination_file_path) = os.path.split(args.dst)
        compression = (
            Compression[args.compression] if args.compression is not None else None
        )

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_file_path = os.path.join(
                temporary_directory, destination_file_path
            )
            async with aiofiles.open(temporary_file_path, "wb") as f:
                await f.write(data)
            await client.push(
                src_paths=[temporary_file_path],
                container=container,
                dest_path=destination_directory,
                compression=compression,
            )


class FSTailCommand(FSCommand):
    @property
    def description(self) -> str:
        return "Tails a remote file to stdout"

    @property
    def name(self) -> str:
        return "tail"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("src", help="Relatve container source path", type=str)
        super().add_parser_arguments(parser)

    async def run_with_container(
        self, container: FileContainer, args: Namespace, client: Client
    ) -> None:
        async for data in client.tail(
            container=container, path=args.src, stop=signal_handler_event("tail")
        ):
            sys.stdout.buffer.write(data)
            sys.stdout.flush()
