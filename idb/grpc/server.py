#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
from typing import Dict, Optional

from logging import Logger

from idb.grpc.handler import GRPCHandler
from idb.common.types import Server
from idb.utils.typing import none_throws
from idb.common.socket import ports_from_sockets
from grpclib.server import Server as GRPC_Server


class GRPCServer(GRPC_Server, Server):
    def __init__(self, handler: GRPCHandler, logger: Logger) -> None:
        GRPC_Server.__init__(self, [handler], loop=asyncio.get_event_loop())
        self.logger = logger

    @property
    def ports(self) -> Dict[str, Optional[int]]:
        (ipv4, ipv6) = ports_from_sockets(none_throws(self._server).sockets)
        return {"ipv4_grpc_port": ipv4, "ipv6_grpc_port": ipv6}
