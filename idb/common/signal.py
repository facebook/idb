#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import signal
from sys import stderr


def signal_handler_event(name: str) -> asyncio.Event:
    loop = asyncio.get_event_loop()
    stop = asyncio.Event()

    # pyre-fixme[53]: Captured variable `stop` is not annotated.
    def signal_handler(sig: signal.Signals) -> None:
        print(f"\nStopping {name}", file=stderr)
        stop.set()

    for sig in [signal.SIGTERM, signal.SIGINT]:
        loop.add_signal_handler(sig, lambda: signal_handler(sig))

    print(f"Running {name} until ^C", file=stderr)
    return stop
