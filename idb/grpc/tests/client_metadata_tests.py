#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import logging
from unittest import mock

from idb.common import plugin
from idb.grpc.client import Client
from idb.utils.testing import TestCase


class ClientMetadataTest(TestCase):
    def test_client_resolves_scoped_invocation_metadata(self) -> None:
        client = Client(
            stub=mock.MagicMock(),
            companion=mock.MagicMock(),
            logger=logging.getLogger("test"),
        )

        with plugin.scoped_invocation_metadata({"capture": "capture-1"}):
            self.assertEqual("capture-1", client.metadata.get("capture"))

        self.assertNotIn("capture", client.metadata)
