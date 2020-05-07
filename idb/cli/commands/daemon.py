#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
from argparse import SUPPRESS, ArgumentParser, Namespace
from typing import Dict, Optional

from idb.cli import BaseCommand
from idb.common.constants import (
    BASE_IDB_FILE_PATH,
    DEFAULT_DAEMON_GRPC_PORT,
    DEFAULT_DAEMON_PORT,
)
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.signal import signal_handler_event
from idb.common.types import IdbException


class DaemonCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "This command is deprecated. the idb daemon is not used anymore."

    @property
    def name(self) -> str:
        return "daemon"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--daemon-port", help=SUPPRESS, type=int, default=DEFAULT_DAEMON_PORT
        )
        parser.add_argument(
            "--reply-fd",
            help="File descriptor to write port the daemon was started on",
            type=int,
            required=False,
        )
        parser.add_argument(
            "--notifier-path",
            help="path to binary that notifies daemon about devices/simulators.",
            type=str,
            required=False,
        )
        parser.add_argument(
            "--daemon-grpc-port",
            help="Port for the daemon to listen to grpc on",
            type=int,
            default=DEFAULT_DAEMON_GRPC_PORT,
        )
        parser.add_argument(
            "--prefer-ipv6",
            help="If set, always return ipv6 port if available when --reply-fd is used",
            action="store_true",
            default=False,
        )
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        self.logger.error(
            "idb daemon is deprecated and does nothing, please remove usages of it."
        )
        os.makedirs(BASE_IDB_FILE_PATH, exist_ok=True)
        companion_manager = DirectCompanionManager(logger=self.logger)
        try:
            companions = await companion_manager.get_companions()
            if len(companions):
                self.logger.info(f"Clearing existing companions {companions}")
            await companion_manager.clear()
            # leaving the daemon command with a dummy output
            # will remove after all uses are removed
            ports = {"ipv4_grpc_port": 0, "ipv6_grpc_port": 0}
            print(json.dumps(ports), sep="\n", flush=True)
            self._reply_with_port(args.reply_fd, args.prefer_ipv6, ports)
            await signal_handler_event("server").wait()
        except IdbException as ex:
            self.logger.exception("Exception in main")
            raise ex
        finally:
            companions = await companion_manager.get_companions()
            if len(companions):
                self.logger.info(f"Clearing existing companions {companions}")
            await companion_manager.clear()
            self.logger.info("Exiting")

    def _reply_with_port(
        self, reply_fd: Optional[int], prefer_ipv6: bool, ports: Dict[str, int]
    ) -> None:
        if not reply_fd:
            return

        prefix = "ipv6_" if prefer_ipv6 else "ipv4_"
        all_ports = {
            key.split(prefix)[1]: value
            for (key, value) in ports.items()
            if key.startswith(prefix)
        }
        self.logger.info(f"Replying to fd {reply_fd} with {all_ports}")
        with os.fdopen(reply_fd, "w") as f:
            f.write(json.dumps(all_ports) + "\n")
