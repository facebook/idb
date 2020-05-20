#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
from abc import abstractmethod
from argparse import ArgumentParser, Namespace
from typing import Any, List, NamedTuple, Optional, Tuple

from idb.cli import ClientCommand
from idb.common.types import IdbClient


class NoBundleIdentifierProvidedException(BaseException):
    pass


class BundleWithPath(NamedTuple):
    bundle_id: Optional[str]
    path: str

    @classmethod
    def parse(cls, argument: str) -> "BundleWithPath":
        split = argument.split(sep=":", maxsplit=1)
        if len(split) == 1:
            return BundleWithPath(bundle_id=None, path=split[0])
        return BundleWithPath(bundle_id=split[0], path=split[1])


def _extract_bundle_id(args: Namespace) -> str:
    if args.bundle_id:
        return args.bundle_id
    values = []
    for value in vars(args).values():
        if isinstance(value, List):
            values.extend(value)
        else:
            values.append(value)
    for value in values:
        if not isinstance(value, BundleWithPath):
            continue
        bundle_id = value.bundle_id
        if bundle_id is None:
            continue
        args.bundle_id = bundle_id
        return args.bundle_id
    raise NoBundleIdentifierProvidedException(f"No Bundle ID Provided in args {args}")


def _convert_args(args: Namespace) -> Tuple[Namespace, str]:
    def convert_value(value: Any) -> Any:  # pyre-ignore
        if isinstance(value, List):
            return [convert_value(x) for x in value]
        return value.path if isinstance(value, BundleWithPath) else value

    bundle_id = _extract_bundle_id(args)
    args = Namespace(
        **{
            key: convert_value(value)
            for (key, value) in vars(args).items()
            if key != "bundle_id"
        }
    )
    return (args, bundle_id)


class FSCommand(ClientCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--bundle-id",
            help="Bundle ID of application. Must be provi",
            type=str,
            required=False,
            default=None,
        )
        super().add_parser_arguments(parser)

    @abstractmethod
    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        pass

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        (args, bundle_id) = _convert_args(args)
        return await self.run_with_bundle(bundle_id=bundle_id, args=args, client=client)


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
            "path", help="Source path", default="./", type=BundleWithPath.parse
        )
        super().add_parser_arguments(parser)

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        paths = await client.ls(bundle_id=bundle_id, path=args.path)
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
            "path", help="Path to directory to create", type=BundleWithPath.parse
        )

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        await client.mkdir(bundle_id=bundle_id, path=args.path)


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
            type=BundleWithPath.parse,
        )
        parser.add_argument(
            "dst",
            help="Destination path relative to Container",
            type=BundleWithPath.parse,
        )
        super().add_parser_arguments(parser)

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        await client.mv(bundle_id=bundle_id, src_paths=args.src, dest_path=args.dst)


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
            type=BundleWithPath.parse,
        )
        super().add_parser_arguments(parser)

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        await client.rm(bundle_id=bundle_id, paths=args.path)


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
            type=BundleWithPath.parse,
        )
        super().add_parser_arguments(parser)

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        return await client.push(
            bundle_id=bundle_id,
            src_paths=[os.path.abspath(path) for path in args.src_paths],
            dest_path=args.dest_path,
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
            "src", help="Relative Container source path", type=BundleWithPath.parse
        )
        parser.add_argument("dst", help="Local destination path", type=str)
        super().add_parser_arguments(parser)

    async def run_with_bundle(
        self, bundle_id: str, args: Namespace, client: IdbClient
    ) -> None:
        await client.pull(
            bundle_id=bundle_id, src_path=args.src, dest_path=os.path.abspath(args.dst)
        )


class DeprecatedPushCommand(ClientCommand):
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
            "bundle_id", help="Bundle id of the app to contain these files", type=str
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

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        self.logger.warning(f"'push' is deprecated, please use 'file push' instead")
        return await FSPushCommand().run_with_bundle(
            bundle_id=args.bundle_id, args=args, client=client
        )


class DeprecatedPullCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Copy a file inside an application's container"

    @property
    def name(self) -> str:
        return "pull"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "bundle_id", help="Bundle id of the app to contain these files", type=str
        )
        parser.add_argument("src", help="Relativer Container source path", type=str)
        parser.add_argument("dst", help="Local destination path", type=str)
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: IdbClient) -> None:
        self.logger.warning(f"'pull' is deprecated, please use 'file pull' instead")
        return await FSPullCommand().run_with_bundle(
            bundle_id=args.bundle_id, args=args, client=client
        )
