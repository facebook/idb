#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import signal
from sys import stderr


def signal_handler_event(name: str) -> asyncio.Event:
    loop = asyncio.get_event_loop()
    stop = asyncio.Event()

    def signal_handler(sig: signal.Signals) -> None:
        print(f"\nStopping {name}", file=stderr)  # pyre-ignore
        stop.set()

    for sig in [signal.SIGTERM, signal.SIGINT]:
        loop.add_signal_handler(sig, lambda: signal_handler(sig))

    print(f"Running {name} until ^C", file=stderr)  # pyre-ignore
    return stop
