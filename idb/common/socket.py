#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from socket import AF_INET, AF_INET6, AddressFamily, socket
from typing import List, Optional, Tuple


def port_from_sockets(sockets: List[socket], family: AddressFamily) -> Optional[int]:
    for sock in sockets:
        if sock.family == family:
            return sock.getsockname()[1]
    return None


def ports_from_sockets(sockets: List[socket]) -> Tuple[Optional[int], Optional[int]]:
    return (port_from_sockets(sockets, AF_INET), port_from_sockets(sockets, AF_INET6))
