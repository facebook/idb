#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import signal
from sys import stderr


def signal_handler_event(name: str) -> asyncio.Event:
    loop = asyncio.get_event_loop()
    stop = asyncio.Event()

    def signal_handler(sig):
        print(f"\nStopping {name}", file=stderr)
        stop.set()

    for sig in [signal.SIGTERM, signal.SIGINT]:
        loop.add_signal_handler(sig, lambda: signal_handler(sig))

    # pyre-fixme[6]: Expected `Optional[_Writer]` for 2nd param but got `TextIO`.
    print(f"Running {name} until ^C", file=stderr)
    return stop
