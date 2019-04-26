#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from unittest import mock
from typing import List

from idb.common.types import TargetDescription
from idb.daemon.companion_tailer import CompanionTailer
from idb.manager.companion import CompanionManager
from idb.utils.testing import AsyncMock, TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class CompanionTailerTest(TestCase):
    async def test_spawn_companion(self) -> None:
        tailer = CompanionTailer("idb_path", mock.Mock())
        tailer._log_file_path = mock.Mock()
        with mock.patch(
            "idb.daemon.companion_tailer.asyncio.create_subprocess_exec",
            new=AsyncMock(),
        ) as exec_mock, mock.patch("idb.daemon.companion_tailer.open"):
            process_mock = mock.Mock()
            process_mock.stdout.readline = AsyncMock(return_value=None)
            exec_mock.return_value = process_mock
            await tailer.start()
            exec_mock.assert_called_once_with(
                "idb_path", "--notify", "1", stdout=mock.ANY, stderr=mock.ANY
            )
            self.assertEqual(tailer.process, process_mock)

    async def test_close(self) -> None:
        tailer = CompanionTailer("idb_path", mock.Mock())
        process_mock = mock.Mock()
        tailer.process = process_mock
        tailer._reading_forever_fut = mock.Mock()
        tailer.close()
        process_mock.terminate.assert_called_once()
        tailer._reading_forever_fut.cancel.assert_called_once()

    async def test_read_stream(self) -> None:
        class StreamMock:
            i = 0
            lines: List[bytes] = [
                json.dumps(
                    {
                        "udid": "udid",
                        "state": "state",
                        "type": "type",
                        "name": "name",
                        "os_version": "os_version",
                        "architecture": "architecture",
                    }
                ).encode("utf-8"),
                json.dumps({"initial_state_ended": True}).encode("utf-8"),
            ]

            async def readline(self) -> bytes:
                result = self.lines[self.i]
                self.i += 1
                return result

        manager = CompanionManager(None, mock.MagicMock())
        tailer = CompanionTailer("idb_path", manager)
        await tailer._read_stream(StreamMock())  # pyre-ignore
        self.assertEqual(
            manager._udid_target_map,
            {
                "udid": TargetDescription(
                    udid="udid",
                    name="name",
                    state="state",
                    target_type="type",
                    os_version="os_version",
                    architecture="architecture",
                    companion_info=None,
                    screen_dimensions=None,
                )
            },
        )
