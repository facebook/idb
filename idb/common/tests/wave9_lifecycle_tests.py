#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import json
import logging
import os
import socket
import subprocess
import tempfile
from datetime import timedelta
from pathlib import Path
from unittest import mock

from idb.common.companion import (
    _terminate_process,
    Companion,
    CompanionServerConfig,
    CompanionSpawnerException,
    DEFAULT_COMPANION_COMMAND_TIMEOUT,
    DEFAULT_COMPANION_TEARDOWN_TIMEOUT,
    DEFAULT_ERASE_COMMAND_TIMEOUT,
)
from idb.common.format import json_format_target_info
from idb.common.types import (
    CompanionInfo,
    DomainSocketAddress,
    IdbException,
    TargetDescription,
    TargetType,
)
from idb.grpc.management import (
    _check_domain_socket_is_bound,
    _local_target_type,
    ClientManager,
)
from idb.utils.testing import TestCase


_PENDING_LIFECYCLE_CORRECTIONS: dict[str, str] = {
    "bounded_readiness": "pending",
    "post_kill_reap": "pending",
    "post_readiness_death_observation": "pending",
    "process_group_cleanup": "pending",
}


def _target(udid: str, target_type: TargetType) -> TargetDescription:
    return TargetDescription(
        udid=udid,
        name=f"target-{udid}",
        target_type=target_type,
        state="Booted",
        os_version="18.0",
        architecture="arm64",
        companion_info=None,
        screen_dimensions=None,
    )


def _reported_process(report: dict[str, int | str]) -> mock.Mock:
    stream = asyncio.StreamReader()
    stream.feed_data(json.dumps(report).encode("utf-8") + b"\n")
    process = mock.Mock()
    process.stdout = stream
    return process


class Wave9LifecycleTests(TestCase):
    async def test_domain_socket_and_tcp_spawn_readiness_argv_primary_mismatch_and_bound_socket_reuse(
        self,
    ) -> None:
        companion = Companion(
            companion_path="idb_companion",
            device_set_path=None,
            logger=mock.Mock(),
        )
        config = CompanionServerConfig(
            udid="test-udid",
            only=TargetType.SIMULATOR,
            log_file_path="companion.log",
            cwd=None,
            tmp_path=None,
            reparent=False,
        )

        with tempfile.TemporaryDirectory() as directory:
            domain_path = str(Path(directory) / "companion.sock")
            domain_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            domain_socket.bind(domain_path)
            domain_socket.listen()
            self.assertTrue(await _check_domain_socket_is_bound(domain_path))
            domain_process = _reported_process({"grpc_path": domain_path})
            opened_log = mock.mock_open()
            with (
                mock.patch(
                    "idb.common.companion.asyncio.create_subprocess_exec",
                    new=mock.AsyncMock(return_value=domain_process),
                ) as create_process,
                mock.patch("idb.common.companion.open", opened_log),
            ):
                spawned = await companion.spawn_domain_sock_server(
                    config=config,
                    path=domain_path,
                )

            self.assertIs(spawned, domain_process)
            create_process.assert_awaited_once_with(
                "idb_companion",
                "--udid",
                "test-udid",
                "--grpc-domain-sock",
                domain_path,
                "--only",
                "simulator",
                stdout=asyncio.subprocess.PIPE,
                stdin=None,
                stderr=opened_log.return_value.__enter__.return_value,
                cwd=None,
                env=os.environ,
                preexec_fn=None,
            )
            duplicate_domain_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                with self.assertRaises(OSError):
                    duplicate_domain_socket.bind(domain_path)
            finally:
                duplicate_domain_socket.close()
                domain_socket.close()
                Path(domain_path).unlink()
            self.assertFalse(await _check_domain_socket_is_bound(domain_path))

        bound_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        bound_socket.bind(("127.0.0.1", 0))
        bound_socket.listen()
        bound_port = bound_socket.getsockname()[1]
        tcp_process = _reported_process({"grpc_port": bound_port})
        opened_log = mock.mock_open()
        with (
            mock.patch(
                "idb.common.companion.asyncio.create_subprocess_exec",
                new=mock.AsyncMock(return_value=tcp_process),
            ) as create_process,
            mock.patch("idb.common.companion.open", opened_log),
        ):
            spawned, reported_port, swift_port = await companion.spawn_tcp_server(
                config=config,
                port=None,
            )

        self.assertIs(spawned, tcp_process)
        self.assertEqual(reported_port, bound_port)
        self.assertIsNone(swift_port)
        create_process.assert_awaited_once_with(
            "idb_companion",
            "--udid",
            "test-udid",
            "--grpc-port",
            "0",
            "--only",
            "simulator",
            stdout=asyncio.subprocess.PIPE,
            stdin=None,
            stderr=opened_log.return_value.__enter__.return_value,
            cwd=None,
            env=os.environ,
            preexec_fn=None,
        )
        duplicate_tcp_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            with self.assertRaises(OSError):
                duplicate_tcp_socket.bind(("127.0.0.1", bound_port))
        finally:
            duplicate_tcp_socket.close()

        requested_port = bound_port - 1 if bound_port == 65535 else bound_port + 1
        mismatch_process = _reported_process({"grpc_port": bound_port})
        with (
            mock.patch(
                "idb.common.companion.asyncio.create_subprocess_exec",
                new=mock.AsyncMock(return_value=mismatch_process),
            ) as create_process,
            mock.patch("idb.common.companion.open", mock.mock_open()),
            mock.patch(
                "idb.common.companion.get_last_n_lines", return_value=["stderr"]
            ),
        ):
            with self.assertRaises(CompanionSpawnerException) as mismatch:
                await companion.spawn_tcp_server(config=config, port=requested_port)
        self.assertEqual(
            str(mismatch.exception),
            "Failed to spawn companion, invalid grpc_port "
            f"(expected {requested_port} got {bound_port})stderr: ['stderr']",
        )
        create_process_args = create_process.await_args
        self.assertIsNotNone(create_process_args)
        assert create_process_args is not None
        self.assertEqual(
            create_process_args.args,
            (
                "idb_companion",
                "--udid",
                "test-udid",
                "--grpc-port",
                str(requested_port),
                "--only",
                "simulator",
            ),
        )

        bound_socket.close()
        reusable_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            reusable_socket.bind(("127.0.0.1", bound_port))
            self.assertEqual(reusable_socket.getsockname()[1], bound_port)
        finally:
            reusable_socket.close()

        reused_udid = "reused-udid"
        reused_path = f"/tmp/idb/{reused_udid}_companion.sock"
        reused = CompanionInfo(
            udid=reused_udid,
            address=DomainSocketAddress(path=reused_path),
            is_local=True,
            pid=867,
        )
        manager = ClientManager(companion_path="idb_companion", logger=mock.Mock())
        manager._companion_set = mock.MagicMock()
        manager._companion_set.add_companion = mock.AsyncMock()
        assert manager._companion is not None
        manager._companion.spawn_domain_sock_server = mock.AsyncMock()
        manager.connect = mock.AsyncMock(return_value=reused)
        with (
            mock.patch(
                "idb.grpc.management._local_target_type",
                new=mock.AsyncMock(return_value=TargetType.SIMULATOR),
            ) as local_target_type,
            mock.patch(
                "idb.grpc.management._check_domain_socket_is_bound",
                new=mock.AsyncMock(return_value=True),
            ) as socket_is_bound,
        ):
            actual = await manager._spawn_companion_server(reused_udid)

        self.assertIs(actual, reused)
        local_target_type.assert_awaited_once_with(
            companion=manager._companion,
            udid=reused_udid,
        )
        socket_is_bound.assert_awaited_once_with(path=reused_path)
        manager.connect.assert_awaited_once_with(
            destination=DomainSocketAddress(path=reused_path)
        )
        manager._companion.spawn_domain_sock_server.assert_not_awaited()
        manager._companion_set.add_companion.assert_awaited_once_with(reused)

        self.assertEqual(_PENDING_LIFECYCLE_CORRECTIONS["bounded_readiness"], "pending")

    async def test_local_target_type_resolution_and_missing_target(self) -> None:
        companion = mock.MagicMock(spec=Companion)
        simulator = _target("simulator-udid", TargetType.SIMULATOR)
        device = _target("device-udid", TargetType.DEVICE)
        companion.list_targets = mock.AsyncMock(return_value=[simulator, device])

        self.assertEqual(await _local_target_type(companion, "mac"), TargetType.MAC)
        companion.list_targets.assert_not_awaited()
        self.assertEqual(
            await _local_target_type(companion, "simulator-udid"),
            TargetType.SIMULATOR,
        )
        self.assertEqual(
            await _local_target_type(companion, "device-udid"),
            TargetType.DEVICE,
        )
        with self.assertRaisesRegex(
            IdbException,
            "Cannot spawn companion for missing-udid, no matching target",
        ):
            await _local_target_type(companion, "missing-udid")
        self.assertEqual(
            companion.list_targets.await_args_list,
            [mock.call(only=None), mock.call(only=None), mock.call(only=None)],
        )

    async def test_lifecycle_subprocess_argv_results_timeouts_and_exit_errors(
        self,
    ) -> None:
        companion = Companion(
            companion_path="idb_companion",
            device_set_path=None,
            logger=mock.Mock(),
        )
        created = _target("created-udid", TargetType.SIMULATOR)
        cloned = _target("cloned-udid", TargetType.SIMULATOR)
        timeout = timedelta(seconds=7)
        run_command = mock.AsyncMock(
            side_effect=[
                f"progress\n{json_format_target_info(created)}\n",
                f"{json_format_target_info(cloned)}\n",
                "",
                "",
                "",
                "",
                "",
            ]
        )
        companion._run_companion_command = run_command

        self.assertEqual(
            await companion.create("iPhone 16", "iOS 18", timeout=timeout),
            created,
        )
        self.assertEqual(
            await companion.clone(
                "source-udid",
                destination_device_set="destination-set",
                timeout=timeout,
            ),
            cloned,
        )
        await companion.boot("boot-udid", verify=False, timeout=timeout)
        await companion.shutdown("shutdown-udid", timeout=timeout)
        await companion.erase("erase-udid")
        await companion.delete("delete-udid", timeout=timeout)
        await companion.delete(None, timeout=timeout)

        self.assertEqual(
            run_command.await_args_list,
            [
                mock.call(arguments=["--create", "iPhone 16,iOS 18"], timeout=timeout),
                mock.call(
                    arguments=[
                        "--clone",
                        "source-udid",
                        "--clone-destination-set",
                        "destination-set",
                    ],
                    timeout=timeout,
                ),
                mock.call(arguments=["--boot", "boot-udid"], timeout=timeout),
                mock.call(arguments=["--shutdown", "shutdown-udid"], timeout=timeout),
                mock.call(
                    arguments=["--erase", "erase-udid"],
                    timeout=DEFAULT_ERASE_COMMAND_TIMEOUT,
                ),
                mock.call(arguments=["--delete", "delete-udid"], timeout=timeout),
                mock.call(arguments=["--delete", "all"], timeout=timeout),
            ],
        )
        self.assertNotIn(
            "--verify-booted",
            run_command.await_args_list[2].kwargs["arguments"],
        )

        command_companion = Companion(
            companion_path="idb_companion",
            device_set_path=None,
            logger=mock.Mock(),
        )
        process = mock.Mock(returncode=0)
        communicate = object()
        process.communicate.return_value = communicate
        command_context = mock.MagicMock()
        command_context.__aenter__ = mock.AsyncMock(return_value=process)
        command_context.__aexit__ = mock.AsyncMock(return_value=False)
        with (
            mock.patch.object(
                command_companion,
                "_start_companion_command",
                return_value=command_context,
            ),
            mock.patch(
                "idb.common.companion.asyncio.wait_for",
                new=mock.AsyncMock(return_value=(b"result", b"")),
            ) as wait_for,
        ):
            self.assertEqual(
                await command_companion._run_companion_command(
                    ["--list", "1"], timeout=None
                ),
                "result",
            )
        wait_for.assert_awaited_once_with(
            communicate,
            timeout=DEFAULT_COMPANION_COMMAND_TIMEOUT.total_seconds(),
        )

        process = mock.Mock(returncode=17)
        process.communicate.return_value = object()
        command_context.__aenter__.return_value = process
        with (
            mock.patch.object(
                command_companion,
                "_start_companion_command",
                return_value=command_context,
            ),
            mock.patch(
                "idb.common.companion.asyncio.wait_for",
                new=mock.AsyncMock(return_value=(b"failed output", b"")),
            ),
        ):
            with self.assertRaises(IdbException) as exited:
                await command_companion._run_companion_command(
                    ["--erase", "udid"], timeout
                )
        self.assertEqual(str(exited.exception), "Failed to run ['--erase', 'udid']")

        process = mock.Mock(returncode=None)
        process.communicate.return_value = object()
        command_context.__aenter__.return_value = process
        with (
            mock.patch.object(
                command_companion,
                "_start_companion_command",
                return_value=command_context,
            ),
            mock.patch(
                "idb.common.companion.asyncio.wait_for",
                new=mock.AsyncMock(side_effect=asyncio.TimeoutError),
            ),
        ):
            with self.assertRaises(IdbException) as timed_out:
                await command_companion._run_companion_command(
                    ["--shutdown", "udid"], timeout
                )
        self.assertEqual(
            str(timed_out.exception),
            "Timed out after 0:00:07 secs on command --shutdown udid",
        )

    async def test_headless_boot_readiness_signal_lifetime_and_cleanup(self) -> None:
        logger = mock.Mock(spec=logging.Logger)
        logger.getEffectiveLevel.return_value = logging.INFO
        child_logger = mock.Mock(spec=logging.Logger)
        logger.getChild.return_value = child_logger
        companion = Companion(
            companion_path="idb_companion",
            device_set_path=None,
            logger=logger,
        )
        target = _target("headless-udid", TargetType.SIMULATOR)
        process = mock.Mock(pid=1234)
        process.stdout.readline = mock.AsyncMock(
            return_value=json_format_target_info(target).encode("utf-8") + b"\n"
        )
        create_process = mock.AsyncMock(return_value=process)
        terminate_process = mock.AsyncMock()
        timeout = timedelta(seconds=9)

        with (
            mock.patch(
                "idb.common.companion.asyncio.create_subprocess_exec",
                new=create_process,
            ),
            mock.patch(
                "idb.common.companion._terminate_process",
                new=terminate_process,
            ),
            mock.patch(
                "idb.common.companion.asyncio.wait_for", wraps=asyncio.wait_for
            ) as wait_for,
        ):
            async with companion.boot_headless(
                udid="headless-udid",
                timeout=timeout,
            ):
                terminate_process.assert_not_awaited()
                process.stdout.readline.assert_awaited_once_with()

        create_process.assert_awaited_once_with(
            "idb_companion",
            "--headless",
            "1",
            "--boot",
            "headless-udid",
            "--verify-booted",
            "1",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        logger.getChild.assert_called_once_with(
            "1234:idb_companion --headless 1 --boot headless-udid --verify-booted 1"
        )
        terminate_process.assert_awaited_once_with(
            process=process,
            timeout=DEFAULT_COMPANION_TEARDOWN_TIMEOUT,
            logger=child_logger,
        )
        wait_for_args = wait_for.await_args
        self.assertIsNotNone(wait_for_args)
        assert wait_for_args is not None
        self.assertEqual(wait_for_args.kwargs["timeout"], 9)

        self.assertEqual(
            _PENDING_LIFECYCLE_CORRECTIONS["post_readiness_death_observation"],
            "pending",
        )

    async def test_sigterm_timeout_sigkill_and_process_group_cleanup(self) -> None:
        logger = mock.Mock(spec=logging.Logger)
        exited = mock.Mock(returncode=None)
        exited.terminate = mock.Mock()
        exited.wait = mock.AsyncMock(return_value=23)
        exited.kill = mock.Mock()

        await _terminate_process(exited, timedelta(seconds=5), logger)

        exited.terminate.assert_called_once_with()
        exited.wait.assert_awaited_once_with()
        exited.kill.assert_not_called()

        stuck = mock.Mock(returncode=None)
        stuck.terminate = mock.Mock()
        stuck.wait = mock.AsyncMock(side_effect=asyncio.TimeoutError)
        stuck.kill = mock.Mock()
        calls = mock.Mock()
        calls.attach_mock(stuck.terminate, "terminate")
        calls.attach_mock(stuck.wait, "wait")
        calls.attach_mock(stuck.kill, "kill")
        with mock.patch("idb.common.companion.os.killpg") as kill_process_group:
            await _terminate_process(stuck, timedelta(milliseconds=1), logger)

        self.assertEqual(
            calls.mock_calls,
            [mock.call.terminate(), mock.call.wait(), mock.call.kill()],
        )
        stuck.wait.assert_awaited_once_with()
        kill_process_group.assert_not_called()

        self.assertEqual(
            {
                name: _PENDING_LIFECYCLE_CORRECTIONS[name]
                for name in ("post_kill_reap", "process_group_cleanup")
            },
            {"post_kill_reap": "pending", "process_group_cleanup": "pending"},
        )
