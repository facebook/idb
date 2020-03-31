#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
from unittest import mock

from idb.common.companion_spawner import CompanionSpawner
from idb.common.constants import IDB_LOCAL_TARGETS_FILE
from idb.utils.testing import AsyncMock, TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionSpawnerTest(TestCase):
    async def test_spawn_companion(self) -> None:
        spawner = CompanionSpawner("idb_path", logger=mock.Mock())
        spawner._log_file_path = mock.Mock()
        spawner.pid_saver = mock.Mock()
        udid = "someUdid"
        with mock.patch(
            "idb.common.companion_spawner.asyncio.create_subprocess_exec",
            new=AsyncMock(),
        ) as exec_mock, mock.patch("idb.common.companion_spawner.open"):
            process_mock = mock.Mock()
            process_mock.stdout.readline = AsyncMock(
                return_value=json.dumps(
                    {"hostname": "myHost", "grpc_port": 1234}
                ).encode("utf-8")
            )
            exec_mock.return_value = process_mock
            port = await spawner.spawn_companion(udid)
            exec_mock.assert_called_once_with(
                "idb_path",
                "--udid",
                "someUdid",
                "--grpc-port",
                "0",
                stdout=mock.ANY,
                stderr=mock.ANY,
                stdin=mock.ANY,
                cwd=None,
                preexec_fn=os.setpgrp,
            )
            self.assertEqual(port, 1234)

    async def test_spawn_notifier(self) -> None:
        spawner = CompanionSpawner("idb_path", logger=mock.Mock())
        spawner._log_file_path = mock.Mock()
        spawner._is_notifier_running = mock.Mock(return_value=False)
        spawner.pid_saver = mock.Mock()
        with mock.patch(
            "idb.common.companion_spawner.asyncio.create_subprocess_exec",
            new=AsyncMock(),
        ) as exec_mock, mock.patch("idb.common.companion_spawner.open"):
            process_mock = mock.Mock()
            process_mock.stdout.readline = AsyncMock(
                return_value=json.dumps({"report_initial_state": True}).encode("utf-8")
            )
            exec_mock.return_value = process_mock
            await spawner.spawn_notifier()
            exec_mock.assert_called_once_with(
                "idb_path",
                "--notify",
                IDB_LOCAL_TARGETS_FILE,
                stderr=mock.ANY,
                stdout=mock.ANY,
            )
