#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import os
from unittest import mock

from idb.common.companion import Companion, CompanionServerConfig
from idb.common.types import TargetType
from idb.utils.testing import AsyncMock, TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionTests(TestCase):
    async def test_spawn_tcp_server(self) -> None:
        spawner = Companion(
            companion_path="idb_path", device_set_path=None, logger=mock.Mock()
        )
        spawner._log_file_path = mock.Mock()
        udid = "someUdid"
        with mock.patch(
            "idb.common.companion.asyncio.create_subprocess_exec",
            new=AsyncMock(),
        ) as exec_mock, mock.patch("idb.common.companion.open"):
            process_mock = mock.Mock()
            process_mock.stdout.readline = AsyncMock(
                return_value=json.dumps(
                    {"hostname": "myHost", "grpc_port": 1234}
                ).encode("utf-8")
            )
            exec_mock.return_value = process_mock
            (_, port) = await spawner.spawn_tcp_server(
                config=CompanionServerConfig(
                    udid=udid,
                    only=TargetType.SIMULATOR,
                    log_file_path=None,
                    cwd=None,
                    tmp_path=None,
                    reparent=True,
                ),
                port=None,
            )
            exec_mock.assert_called_once_with(
                "idb_path",
                "--udid",
                "someUdid",
                "--grpc-port",
                "0",
                "--only",
                "simulator",
                stdout=mock.ANY,
                stderr=mock.ANY,
                stdin=mock.ANY,
                cwd=None,
                env=os.environ,
                preexec_fn=os.setpgrp,
            )
            self.assertEqual(port, 1234)
