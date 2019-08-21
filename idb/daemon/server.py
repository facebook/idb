#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
from argparse import Namespace
from logging import Logger
from typing import Dict, List

from idb.common.logging import log_call
from idb.common.types import Server
from idb.grpc.handler import GRPCHandler
from idb.grpc.server import GRPCServer


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
    grpc_handler = GRPCHandler(logger=logger)
    grpc_server = GRPCServer(handler=grpc_handler, logger=logger)
    await grpc_server.start("localhost", grpc_port)
    servers: List[Server] = [grpc_server]
    logger.debug(f"Started servers {servers}")
    return CompositeServer(servers=servers, logger=logger)
