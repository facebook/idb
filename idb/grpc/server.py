#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
from logging import Logger
from typing import Dict, Optional

from grpclib.server import Server as GRPC_Server
from idb.common.socket import ports_from_sockets
from idb.common.types import Server
from idb.grpc.handler import GRPCHandler
from idb.utils.typing import none_throws


class GRPCServer(GRPC_Server, Server):
    def __init__(self, handler: GRPCHandler, logger: Logger) -> None:
        # pyre-fixme[6]: Expected `Collection[IServable]` for 2nd param but got
        #  `List[GRPCHandler]`.
        GRPC_Server.__init__(self, [handler], loop=asyncio.get_event_loop())
        self.logger = logger

    @property
    def ports(self) -> Dict[str, Optional[int]]:
        # pyre-fixme[6]: Expected `List[socket]` for 1st param but got
        #  `Optional[List[socket]]`.
        (ipv4, ipv6) = ports_from_sockets(none_throws(self._server).sockets)
        return {"ipv4_grpc_port": ipv4, "ipv6_grpc_port": ipv6}
