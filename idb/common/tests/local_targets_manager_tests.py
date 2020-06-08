#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import tempfile
from unittest import mock

from idb.common.local_targets_manager import LocalTargetsManager
from idb.common.types import TargetDescription
from idb.utils.testing import TestCase, ignoreTaskLeaks


notifier_output = '[{"os_version":"iOS 12.4","state":"Shutdown","architecture":"x86_64","type":"simulator","udid":"AADCF696-ADFA-4D1B-834A-451B6AD7CA27","name":"iPhone 7 Plus"}]'


@ignoreTaskLeaks
class LocalTargetsManagerTests(TestCase):
    async def test_get_local_targets(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            local_targets_manager = LocalTargetsManager(
                logger=mock.MagicMock(), local_targets_file=f.name
            )
            with open(f.name, "w") as f:
                f.write(notifier_output)
            targets = await local_targets_manager.get_local_targets()
            target: TargetDescription = targets[0]
            self.assertEqual(target.udid, "AADCF696-ADFA-4D1B-834A-451B6AD7CA27")
            self.assertEqual(target.state, "Shutdown")
            self.assertEqual(target.architecture, "x86_64")
            self.assertEqual(target.target_type, "simulator")
            self.assertEqual(target.name, "iPhone 7 Plus")
