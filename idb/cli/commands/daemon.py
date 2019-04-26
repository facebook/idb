#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
import os
from argparse import ArgumentParser, Namespace
from typing import Optional, Dict

from idb.common.signal import signal_handler_event
from idb.cli.commands.base import BaseCommand
from idb.client.daemon_pid_saver import remove_daemon_pid, save_daemon_pid
from idb.common.constants import DEFAULT_DAEMON_GRPC_PORT, DEFAULT_DAEMON_PORT
from idb.daemon.server import start_daemon_server
from idb.common.types import Server, IdbException


class DaemonCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "Start the daemon"

    @property
    def name(self) -> str:
        return "daemon"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "--daemon-port",
            help="Port for the daemon to listen on",
            type=int,
            default=DEFAULT_DAEMON_PORT,
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
        server: Optional[Server] = None
        try:
            server = await start_daemon_server(args=args, logger=self.logger)
            save_daemon_pid(pid=os.getpid())
            print(json.dumps(server.ports), sep="\n", flush=True)
            self._reply_with_port(args.reply_fd, args.prefer_ipv6, server.ports)
            await signal_handler_event("server").wait()
        except IdbException as ex:
            self.logger.exception("Exception in main")
            raise ex
        finally:
            remove_daemon_pid(pid=os.getpid())
            if server:
                server.close()
                await server.wait_closed()
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
