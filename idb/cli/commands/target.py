#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import json
from argparse import ArgumentParser, Namespace, SUPPRESS
from typing import Mapping, Union

import idb.common.plugin as plugin
from idb.cli import ClientCommand, CompanionCommand, ManagementCommand
from idb.common.format import human_format_target_info, json_format_target_info
from idb.common.signal import signal_handler_event
from idb.common.types import (
    Client,
    ClientManager,
    Companion,
    IdbException,
    TargetType,
    TCPAddress,
)
from idb.common.udid import is_udid


class DestinationCommandException(Exception):
    pass


class ConnectCommandException(Exception):
    pass


class DisconnectCommandException(Exception):
    pass


def get_destination(args: Namespace) -> Union[TCPAddress, str]:
    if is_udid(args.companion):
        return args.companion
    elif args.port and args.companion:
        return TCPAddress(host=args.companion, port=args.port)
    else:
        raise DestinationCommandException(
            "provide either a UDID or the host and port of the companion"
        )


class TargetConnectCommand(ManagementCommand):
    @property
    def description(self) -> str:
        return "Connect to a companion"

    @property
    def name(self) -> str:
        return "connect"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "companion",
            help="Host the companion is running on. or the UDID of the target",
            type=str,
        )
        parser.add_argument(
            "port",
            help="Port the companion is running on",
            type=int,
            nargs="?",
            default=None,
        )
        # not used and suppressed. remove after the removal of thrift is deployed everywhere
        parser.add_argument(
            "grpc_port", help=SUPPRESS, type=int, nargs="?", default=None
        )
        super().add_parser_arguments(parser)

    async def run_with_manager(self, args: Namespace, manager: ClientManager) -> None:
        try:
            destination = get_destination(args=args)
            response = await manager.connect(
                destination=destination,
                metadata={
                    key: value
                    for (key, value) in plugin.resolve_metadata(self.logger).items()
                    if isinstance(value, str)
                },
            )
            if args.json:
                print(
                    json.dumps(
                        {
                            "udid": response.udid,
                            "is_local": response.is_local,
                            "metadata": response.metadata,
                        }
                    )
                )
            else:
                print(f"udid: {response.udid} is_local: {response.is_local}")

        except IdbException:
            raise ConnectCommandException(
                f"""Could not connect to {args.companion:}:{args.port}.
            Make sure both host and port are correct and reachable"""
            )


class TargetDisconnectCommand(ManagementCommand):
    @property
    def description(self) -> str:
        return "Disconnect a companion"

    @property
    def name(self) -> str:
        return "disconnect"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "companion",
            help="Host the companion is running on or the udid of the target",
            type=str,
        )
        parser.add_argument(
            "port",
            help="Port the companion is running on",
            type=int,
            nargs="?",
            default=None,
        )
        super().add_parser_arguments(parser)

    async def run_with_manager(self, args: Namespace, manager: ClientManager) -> None:
        try:
            destination = get_destination(args=args)
            await manager.disconnect(destination=destination)
        except IdbException:
            raise DisconnectCommandException(
                f"Could not disconnect from {args.companion:}:{args.port}"
            )


class TargetDescribeCommand(ClientCommand):
    @property
    def description(self) -> str:
        return "Describes the Target"

    @property
    def name(self) -> str:
        return "describe"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--diagnostics",
            help="Fetch additional target diagnostics",
            action="store_true",
            default=False,
        )
        super().add_parser_arguments(parser)

    async def run_with_client(self, args: Namespace, client: Client) -> None:
        description = await client.describe(fetch_diagnostics=args.diagnostics)
        if args.json:
            print(description.as_json)
        else:
            print(description)


_STRING_TO_ONLY: Mapping[str, TargetType] = {
    target_type.value: target_type for target_type in TargetType
}


class TargetListCommand(ManagementCommand):
    @property
    def description(self) -> str:
        return "Lists connected and available targets"

    @property
    def name(self) -> str:
        return "list-targets"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--only",
            help="Which device types to list. Specifying a filter will make this command run faster.",
            choices=list(_STRING_TO_ONLY.keys()),
            default=None,
            required=False,
        )
        super().add_parser_arguments(parser)

    async def run_with_manager(self, args: Namespace, manager: ClientManager) -> None:
        only = _STRING_TO_ONLY[args.only] if args.only is not None else None
        targets = await manager.list_targets(only=only)
        if len(targets) == 0:
            if not args.json:
                print("No available targets")
            return

        targets = sorted(targets, key=lambda target: target.name)
        formatter = human_format_target_info
        if args.json:
            formatter = json_format_target_info
        for target in targets:
            print(formatter(target))


class TargetCreateCommand(CompanionCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument("device_type", help="The Device Type to create", type=str)
        parser.add_argument("os_version", help="The OS Version to create", type=str)
        super().add_parser_arguments(parser)

    @property
    def description(self) -> str:
        return "Creates an iOS Simulator"

    @property
    def name(self) -> str:
        return "create"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        target = await companion.create(
            device_type=args.device_type, os_version=args.os_version
        )
        print(target.udid)


class UDIDTargetedCompanionCommand(CompanionCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser=parser)
        parser.add_argument("udid", help="The UDID of the target", nargs="?")
        parser.add_argument("--udid", help=SUPPRESS, dest="udid_flag")

    def get_udid(self, args: Namespace) -> str:
        if args.udid:
            return args.udid
        elif args.udid_flag:
            return args.udid_flag
        raise Exception("Need to provide udid as a position argument")


class TargetBootCommand(UDIDTargetedCompanionCommand):
    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        super().add_parser_arguments(parser)
        parser.add_argument(
            "--headless",
            help="Boot the simulator headlessly. "
            "This means that the lifecycles of the Simulator is tied to the lifecycle of this idb process. "
            "Helpful when you wish to have subprocess-termination act teardown the Simulator.",
            default=False,
            action="store_true",
        )

    @property
    def description(self) -> str:
        return "Boots a simulator (only works on mac)"

    @property
    def name(self) -> str:
        return "boot"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        if args.headless:
            async with companion.boot_headless(udid=self.get_udid(args)):
                await signal_handler_event("headless_boot").wait()
        else:
            await companion.boot(udid=self.get_udid(args))


class TargetShutdownCommand(UDIDTargetedCompanionCommand):
    @property
    def description(self) -> str:
        return "Shuts the simulator down (only works on mac)"

    @property
    def name(self) -> str:
        return "shutdown"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        await companion.shutdown(udid=self.get_udid(args))


class TargetEraseCommand(UDIDTargetedCompanionCommand):
    @property
    def description(self) -> str:
        return "Erases the simulator (only works on mac)"

    @property
    def name(self) -> str:
        return "erase"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        await companion.erase(udid=self.get_udid(args))


class TargetCloneCommand(UDIDTargetedCompanionCommand):
    @property
    def description(self) -> str:
        return "Clones the simulator (only works on mac)"

    @property
    def name(self) -> str:
        return "clone"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        target = await companion.clone(udid=self.get_udid(args))
        print(target.udid)


class TargetDeleteCommand(UDIDTargetedCompanionCommand):
    @property
    def description(self) -> str:
        return "Deletes (only works on mac)"

    @property
    def name(self) -> str:
        return "delete"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        await companion.delete(udid=self.get_udid(args))


class TargetDeleteAllCommand(CompanionCommand):
    @property
    def description(self) -> str:
        return "Deletes all simulators (only works on mac)"

    @property
    def name(self) -> str:
        return "delete-all"

    async def run_with_companion(self, args: Namespace, companion: Companion) -> None:
        await companion.delete(udid=None)
