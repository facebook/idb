#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio

import idb.common.plugin as plugin
from typing import List, Dict
from logging import Logger
from idb.common.types import Server
from idb.manager.companion import CompanionManager
from idb.daemon.companion_tailer import CompanionTailer
from idb.grpc.handler import GRPCHandler
from idb.grpc.server import GRPCServer
from idb.common.logging import log_call
from argparse import Namespace
from idb.common.boot_manager import BootManager


class CompositeServer(Server):
    def __init__(self, servers: List[Server], logger: Logger) -> None:
        self.servers = servers
        self.logger = logger

    def close(self) -> None:
        self.logger.info(f"Stopping {len(self.servers)} servers")
        for server in self.servers:
            self.logger.info(f"Closing {server}")
            server.close()

    async def wait_closed(self) -> None:
        await asyncio.gather(*[server.wait_closed() for server in self.servers])

    @property
    def ports(self) -> Dict[str, str]:
        return {
            key: value
            for server in self.servers
            for (key, value) in server.ports.items()
        }


@log_call()
async def start_daemon_server(args: Namespace, logger: Logger) -> Server:
    grpc_port = args.daemon_grpc_port
    notifier_path = args.notifier_path
    companion_manager = CompanionManager(companion_path=notifier_path, logger=logger)
    boot_manager = BootManager(companion_path=notifier_path)
    grpc_handler = GRPCHandler(
        companion_manager=companion_manager, boot_manager=boot_manager, logger=logger
    )
    grpc_server = GRPCServer(handler=grpc_handler, logger=logger)
    await grpc_server.start("localhost", grpc_port)
    servers: List[Server] = [grpc_server]
    if notifier_path:
        companion_tailer = CompanionTailer(
            notifier_path=notifier_path, companion_manager=companion_manager
        )
        await companion_tailer.start()
        servers.append(companion_tailer)
    servers = await plugin.resolve_servers(
        args=args,
        companion_manager=companion_manager,
        boot_manager=boot_manager,
        logger=logger,
        servers=servers,
    )
    logger.debug(f"Started servers {servers}")
    return CompositeServer(servers=servers, logger=logger)
