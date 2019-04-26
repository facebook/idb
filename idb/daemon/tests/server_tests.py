#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from unittest import mock

from idb.daemon.server import CompositeServer
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class ServerTest(TestCase):
    def test_close(self) -> None:
        first = mock.MagicMock()
        second = mock.MagicMock()
        server = CompositeServer(servers=[first, second], logger=mock.MagicMock())
        server.close()
        first.close.assert_called_once()
        second.close.assert_called_once()
