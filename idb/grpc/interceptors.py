#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os

from grpclib.events import SendRequest


async def on_send_request_set_swift_methods(event: SendRequest) -> None:
    swift_methods = os.environ.get("IDB_SWIFT_METHODS")
    if swift_methods:
        event.metadata["idb-swift-methods"] = swift_methods
