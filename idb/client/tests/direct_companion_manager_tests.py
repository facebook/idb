#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.
import json
import tempfile
from unittest import mock

from idb.client.direct_companion_manager import DirectCompanionManager
from idb.common.format import json_data_companions, json_to_companion_info
from idb.common.types import CompanionInfo
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionManagerTests(TestCase):
    async def test_add_companion(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            companion_manager = DirectCompanionManager(
                logger=mock.MagicMock(), state_file_path=f.name
            )
            companion = CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False
            )
            companion_manager.add_companion(companion)
            data = json.load(f)
            companions = json_to_companion_info(data)
            read_companion: CompanionInfo = companions[0]
            self.assertEqual(companion, read_companion)

    async def test_get_companions(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            companion_manager = DirectCompanionManager(
                logger=mock.MagicMock(), state_file_path=f.name
            )
            companion = CompanionInfo(
                udid="asdasda", host="foohost", port=123, is_local=False
            )
            with open(f.name, "w") as f:
                json.dump(json_data_companions([companion]), f)
            companions = companion_manager._load()
            read_companion: CompanionInfo = companions[0]
            self.assertEqual(companion, read_companion)
