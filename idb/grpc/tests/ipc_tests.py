#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

#
# Copyright 2004-present Facebook.  All rights reserved.
#

import logging
from inspect import Signature, isasyncgenfunction, iscoroutinefunction, signature
from typing import Callable

from idb.grpc.ipc_loader import (
    _client_implementations,
    _daemon_implementations,
    _has_parameter,
    _takes_client,
    _takes_stream,
)
from idb.utils.testing import TestCase


logger: logging.Logger = logging.getLogger(__name__)


class IpcTests(TestCase):
    def test_client_methods(self) -> None:
        for name, client in _client_implementations():
            with self.subTest(name):
                self._test_client_method(client, name)

    def _test_client_method(self, client: Callable, name: str) -> None:
        self.assertTrue(client is not None, f"{name} should have a client method")
        self.assertTrue(
            iscoroutinefunction(client) or isasyncgenfunction(client),
            f"The client method of {name} should be a coroutine",
        )
        self.assertTrue(
            _takes_client(client),
            f"The client method of {name} should take a CompanionClient",
        )

    def test_daemon_methods(self) -> None:
        for name, daemon in _daemon_implementations():
            with self.subTest(name):
                self._test_deamon_method(daemon, name)

    def _test_deamon_method(self, daemon: Callable, name: str) -> None:
        sig = signature(daemon)
        self.assertTrue(
            iscoroutinefunction(daemon),
            f"The daemon method on {name} should be a coroutine",
        )
        returns_obj = (
            sig.return_annotation is not None
            and sig.return_annotation is not Signature.empty
        )
        is_unary_unary = returns_obj and _has_parameter(daemon, "request")
        is_stream = _takes_stream(daemon)
        self.assertTrue(
            is_stream or is_unary_unary,
            f"The daemon method of {name} needs to take a stream or "
            "take a request and return a response",
        )
        if is_stream:
            self.assertTrue(
                not returns_obj,
                f"The daemon method of {name} should not return an object "
                "as it takes a stream",
            )
