#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from unittest import mock

from idb.common.companion_spawner import CompanionSpawner
from idb.utils.testing import AsyncMock, TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionSpawnerTest(TestCase):
    async def test_spawn_companion(self) -> None:
        spawner = CompanionSpawner("idb_path")
        spawner._log_file_path = mock.Mock()
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
                stdout=mock.ANY,
                stdin=mock.ANY,
                stderr=mock.ANY,
            )
            self.assertEqual(port, 1234)
            self.assertEqual(spawner.companion_processes, [process_mock])

    async def test_close(self) -> None:
        spawner = CompanionSpawner("idb_path")
        spawner.companion_processes = [mock.Mock() for _ in range(3)]
        spawner.close()
        for process in spawner.companion_processes:
            process.terminate.assert_called_once()
