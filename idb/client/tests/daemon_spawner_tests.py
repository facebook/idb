#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import json
import os
import signal
import tempfile
from unittest import mock

from idb.client.daemon_pid_saver import (
    _clear_saved_daemon_pids,
    _get_daemon_pids,
    _write_daemon_pids,
    kill_saved_pids,
)
from idb.client.daemon_spawner import DaemonSpawner, DaemonSpawnerException
from idb.common.constants import (
    DEFAULT_DAEMON_HOST,
    DEFAULT_DAEMON_GRPC_PORT,
    IDB_DAEMON_PID_PATH,
)
from idb.utils.testing import AsyncMock, TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class DaemonSpawnerTests(TestCase):
    def setUp(self) -> None:
        self.spawner = DaemonSpawner(
            port=DEFAULT_DAEMON_GRPC_PORT, host=DEFAULT_DAEMON_HOST
        )
        self.spawner.daemon_pids = []

    async def test_start_daemon_if_needed_override(self) -> None:
        self.spawner.port = DEFAULT_DAEMON_GRPC_PORT
        self.spawner.host = "someHost"
        self.spawner._spawn_daemon = AsyncMock()
        await self.spawner.start_daemon_if_needed()
        self.spawner._spawn_daemon.assert_not_called()

    async def test_start_daemon_if_needed_port_open(self) -> None:
        self.spawner._spawn_daemon = AsyncMock()
        with mock.patch("idb.client.daemon_spawner.networking") as networking_mock:
            networking_mock.is_port_open.return_value = False
            await self.spawner.start_daemon_if_needed()
            self.spawner._spawn_daemon.assert_called_once_with()

    async def test_start_daemon_if_needed_force(self) -> None:
        with mock.patch(
            "idb.client.daemon_spawner.kill_saved_pids", AsyncMock()
        ) as kill:
            self.spawner._spawn_daemon = AsyncMock()
            with mock.patch("idb.client.daemon_spawner.networking") as networking_mock:
                networking_mock.is_port_open.return_value = True
                await self.spawner.start_daemon_if_needed(force_kill=True)
                kill.assert_called_once_with()
                self.spawner._spawn_daemon.assert_called_once_with()

    async def test_kill_no_pids(self) -> None:
        _clear_saved_daemon_pids()
        with mock.patch("idb.client.daemon_spawner.os.kill") as kill:
            await kill_saved_pids()
            kill.assert_not_called()

    async def test_kill_with_pids(self) -> None:
        _clear_saved_daemon_pids()
        with mock.patch(
            "idb.client.daemon_pid_saver._get_daemon_pids", return_value=[1, 2]
        ):
            with mock.patch("idb.client.daemon_spawner.os.kill") as kill:
                await kill_saved_pids()
                kill.assert_has_calls(
                    [mock.call(1, signal.SIGTERM), mock.call(2, signal.SIGTERM)]
                )

    async def test_save_daemon_pids(self) -> None:
        _clear_saved_daemon_pids()
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = os.path.join(temp_dir, IDB_DAEMON_PID_PATH)
            _write_daemon_pids(pids=[1, 2])
            with open(file_path, "r") as file:
                self.assertEqual(json.load(file), [1, 2])

    async def test_get_daemon_pids(self) -> None:
        _clear_saved_daemon_pids()
        with tempfile.TemporaryDirectory() as temp_dir:
            file_path = os.path.join(temp_dir, IDB_DAEMON_PID_PATH)
            with open(file_path, "w") as file:
                json.dump([1, 2], file)
            self.assertEqual([1, 2], _get_daemon_pids())

    async def test_spawn_daemon(self) -> None:
        await self.spawn_daemon(on_darwin=False)

    async def test_spawn_daemon_darwin(self) -> None:
        await self.spawn_daemon(on_darwin=True)

    async def spawn_daemon(self, on_darwin: bool) -> None:
        _clear_saved_daemon_pids()
        with tempfile.TemporaryDirectory() as temp_dir:
            self.spawner._log_file_path = mock.Mock(return_value=temp_dir + "/daemon")
            self.spawner._read_daemon_output = AsyncMock()
            with mock.patch(
                "idb.client.daemon_spawner.asyncio.create_subprocess_exec",
                new=AsyncMock(),
            ) as exec_mock, mock.patch(
                "idb.client.daemon_spawner.platform.system",
                new=mock.Mock(return_value="Darwin" if on_darwin else "NotDarwin"),
            ), mock.patch(
                "idb.client.daemon_spawner.sys.argv", new=["idb_path"]
            ):
                exec_mock.return_value.pid = 123
                await self.spawner._spawn_daemon()
                exec_mock.assert_called_once_with(
                    "idb_path",
                    "daemon",
                    *(["--notifier-path", "idb_companion"] if on_darwin else []),
                    stdout=asyncio.subprocess.PIPE,
                    stderr=mock.ANY,
                )
                self.assertEqual(_get_daemon_pids(), [123])

    async def test_read_daemon_output_json(self) -> None:
        stream = mock.Mock()
        stream.readline = AsyncMock(return_value=json.dumps({}).encode("utf-8"))
        await self.spawner._read_daemon_output(stream)

    async def test_read_daemon_output_garbage(self) -> None:
        stream = mock.Mock()
        stream.readline = AsyncMock(return_value="trash".encode("utf-8"))
        with self.assertRaises(DaemonSpawnerException):
            await self.spawner._read_daemon_output(stream)
