#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import errno
import multiprocessing
import os
import stat
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Protocol
from unittest import mock

from idb.common.companion_set import _open_lockfile, CompanionSet
from idb.common.types import (
    CompanionInfo,
    DomainSocketAddress,
    IdbException,
    TCPAddress,
)
from idb.utils.testing import ignoreTaskLeaks, TestCase


_ALPHA_STATE_BYTES: bytes = (
    b'[{"udid": "alpha", "is_local": false, "pid": null, '
    b'"host": "127.0.0.1", "port": 10882}]'
)
_CURRENT_STATE_BYTES: bytes = (
    b'[{"udid": "alpha", "is_local": false, "pid": null, '
    b'"host": "127.0.0.1", "port": 10882}, '
    b'{"udid": "zeta", "is_local": true, "pid": 314, '
    b'"path": "/tmp/zeta.sock"}]'
)
_PENDING_CORRECTIONS: dict[str, str] = {
    "atomic_publication": "landed",
    "lock_body_file_exists_error_propagation": "landed",
    "lock_owner_only_cleanup": "landed",
}
_PENDING_RUST_HALVES: dict[str, str] = {
    "rust_reads_python_state": "pending",
    "rust_writes_python_state": "pending",
}


class _ProcessEvent(Protocol):
    def set(self) -> None: ...

    def wait(self, timeout: float | None = None) -> bool: ...


def _hold_lock_in_process(
    state_file_path: str,
    ready: _ProcessEvent,
    release: _ProcessEvent,
) -> None:
    async def hold_lock() -> None:
        async with _open_lockfile(state_file_path):
            ready.set()
            if not release.wait(timeout=10):
                raise TimeoutError("Timed out waiting to release the registry lock")

    asyncio.run(hold_lock())


def _registry_artifacts(state: Path) -> list[Path]:
    temporary_prefix = f".{state.name}."
    return sorted(
        path
        for path in state.parent.iterdir()
        if path.name == f"{state.name}.lock"
        or (path.name.startswith(temporary_prefix) and path.name.endswith(".tmp"))
    )


def _companions() -> list[CompanionInfo]:
    return [
        CompanionInfo(
            udid="alpha",
            address=TCPAddress(host="127.0.0.1", port=10882),
            is_local=False,
            pid=None,
        ),
        CompanionInfo(
            udid="zeta",
            address=DomainSocketAddress(path="/tmp/zeta.sock"),
            is_local=True,
            pid=314,
        ),
    ]


def _manager(path: Path) -> CompanionSet:
    return CompanionSet(logger=mock.MagicMock(), state_file_path=str(path))


@ignoreTaskLeaks
class Wave9StateTests(TestCase):
    async def test_missing_empty_malformed_and_legacy_state(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, initial_bytes in (
                ("missing", None),
                ("empty", b""),
                ("malformed", b"not-json"),
            ):
                with self.subTest(state=name):
                    state = root / name
                    if initial_bytes is not None:
                        state.write_bytes(initial_bytes)
                    self.assertEqual(await _manager(state).get_companions(), [])
                    self.assertEqual(state.read_bytes(), b"[]")
                    self.assertEqual(_registry_artifacts(state), [])

            for name, initial_bytes in (
                ("body-missing", None),
                ("body-malformed", b"not-json"),
            ):
                with self.subTest(state=name):
                    state = root / name
                    if initial_bytes is not None:
                        state.write_bytes(initial_bytes)
                    body_error = RuntimeError(f"{name} body failed")
                    with self.assertRaises(RuntimeError) as raised:
                        async with _manager(state)._use_stored_companions():
                            raise body_error
                    self.assertIs(raised.exception, body_error)
                    if initial_bytes is None:
                        self.assertFalse(state.exists())
                    else:
                        self.assertEqual(state.read_bytes(), initial_bytes)
                    self.assertEqual(_registry_artifacts(state), [])

            for name, valid_empty_bytes in (
                ("empty_object", b"{}"),
                ("empty_string", b'""'),
            ):
                with self.subTest(state=name):
                    state = root / name
                    state.write_bytes(valid_empty_bytes)
                    self.assertEqual(await _manager(state).get_companions(), [])
                    self.assertEqual(state.read_bytes(), valid_empty_bytes)
                    self.assertEqual(_registry_artifacts(state), [])

            for name, wrong_shape_bytes, error in (
                ("nonempty_object", b'{"entry": 1}', TypeError),
                ("missing_fields", b"[{}]", KeyError),
            ):
                with self.subTest(state=name):
                    state = root / name
                    state.write_bytes(wrong_shape_bytes)
                    with self.assertRaises(error):
                        await _manager(state).get_companions()
                    self.assertEqual(state.read_bytes(), wrong_shape_bytes)
                    self.assertEqual(_registry_artifacts(state), [])

            wrong_types = root / "wrong-types"
            wrong_type_bytes = (
                b'[{"udid": 7, "is_local": "yes", "pid": "pid", '
                b'"host": 8, "port": "10882"}]'
            )
            wrong_types.write_bytes(wrong_type_bytes)
            companions = await _manager(wrong_types).get_companions()
            self.assertEqual(companions[0].udid, 7)
            self.assertEqual(companions[0].is_local, "yes")
            self.assertEqual(companions[0].pid, "pid")
            wrong_address = companions[0].address
            self.assertIsInstance(wrong_address, TCPAddress)
            assert isinstance(wrong_address, TCPAddress)
            self.assertEqual(wrong_address.host, 8)
            self.assertEqual(wrong_address.port, "10882")
            self.assertEqual(wrong_types.read_bytes(), wrong_type_bytes)
            self.assertEqual(_registry_artifacts(wrong_types), [])

            unknown_field = root / "unknown-field"
            unknown_field_bytes = (
                b'[{"udid": "unknown", "is_local": false, "pid": null, '
                b'"host": "localhost", "port": 10882, "extra": "preserved"}]'
            )
            unknown_field.write_bytes(unknown_field_bytes)
            unknown_manager = _manager(unknown_field)
            self.assertEqual(
                await unknown_manager.get_companions(),
                [
                    CompanionInfo(
                        udid="unknown",
                        address=TCPAddress(host="localhost", port=10882),
                        is_local=False,
                        pid=None,
                    )
                ],
            )
            self.assertEqual(unknown_field.read_bytes(), unknown_field_bytes)
            await unknown_manager.add_companion(
                CompanionInfo(
                    udid="second",
                    address=DomainSocketAddress(path="/tmp/second.sock"),
                    is_local=True,
                    pid=2718,
                )
            )
            self.assertNotIn(b'"extra"', unknown_field.read_bytes())
            self.assertEqual(_registry_artifacts(unknown_field), [])

            legacy = root / "legacy"
            legacy_bytes = (
                b'[{"udid": "legacy", "is_local": false, '
                b'"host": "localhost", "port": 10882}]'
            )
            legacy.write_bytes(legacy_bytes)
            self.assertEqual(
                await _manager(legacy).get_companions(),
                [
                    CompanionInfo(
                        udid="legacy",
                        address=TCPAddress(host="localhost", port=10882),
                        is_local=False,
                        pid=None,
                    )
                ],
            )
            self.assertEqual(legacy.read_bytes(), legacy_bytes)
            self.assertEqual(_registry_artifacts(legacy), [])

    async def test_sorted_state_schema_and_exact_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            expected = _companions()
            manager = _manager(state)

            await manager.add_companion(expected[1])
            await manager.add_companion(expected[0])
            self.assertEqual(state.read_bytes(), _CURRENT_STATE_BYTES)
            self.assertEqual(stat.S_IMODE(state.stat().st_mode), 0o600)
            with (
                mock.patch("idb.common.companion_set.os.replace") as replace,
                mock.patch(
                    "idb.common.companion_set.tempfile.mkstemp"
                ) as make_temporary,
            ):
                self.assertEqual(await manager.get_companions(), expected)
            replace.assert_not_called()
            make_temporary.assert_not_called()
            self.assertEqual(state.read_bytes(), _CURRENT_STATE_BYTES)
            self.assertEqual(_registry_artifacts(state), [])

            atomic_state = root / "atomic-state"
            atomic_state.write_bytes(b"[]")
            observations: list[tuple[bytes, bytes, int]] = []
            real_replace = os.replace

            def observing_replace(source: str, destination: str) -> None:
                self.assertEqual(Path(source).parent, Path(destination).parent)
                observations.append(
                    (
                        Path(destination).read_bytes(),
                        Path(source).read_bytes(),
                        stat.S_IMODE(Path(source).stat().st_mode),
                    )
                )
                real_replace(source, destination)

            with mock.patch(
                "idb.common.companion_set.os.replace",
                side_effect=observing_replace,
            ):
                await _manager(atomic_state).add_companion(expected[0])
            self.assertEqual(observations, [(b"[]", _ALPHA_STATE_BYTES, 0o600)])
            self.assertEqual(atomic_state.read_bytes(), _ALPHA_STATE_BYTES)
            self.assertEqual(stat.S_IMODE(atomic_state.stat().st_mode), 0o600)
            self.assertEqual(_registry_artifacts(atomic_state), [])

            short_write_state = root / "short-write-state"
            short_write_state.write_bytes(b"[]")
            write_lengths: list[int] = []
            real_write = os.write

            def short_write(descriptor: int, data: bytes) -> int:
                length = max(1, len(data) // 2)
                write_lengths.append(length)
                return real_write(descriptor, data[:length])

            with mock.patch(
                "idb.common.companion_set.os.write",
                side_effect=short_write,
            ):
                await _manager(short_write_state).add_companion(expected[0])
            self.assertGreater(len(write_lengths), 1)
            self.assertEqual(short_write_state.read_bytes(), _ALPHA_STATE_BYTES)
            self.assertEqual(_registry_artifacts(short_write_state), [])

            zero_write_state = root / "zero-write-state"
            zero_write_state.write_bytes(b"[]")
            with mock.patch("idb.common.companion_set.os.write", return_value=0):
                with self.assertRaises(OSError) as raised:
                    await _manager(zero_write_state).add_companion(expected[0])
            self.assertEqual(raised.exception.errno, errno.EIO)
            self.assertEqual(zero_write_state.read_bytes(), b"[]")
            self.assertEqual(_registry_artifacts(zero_write_state), [])

            enospc_state = root / "enospc-state"
            enospc_state.write_bytes(b"[]")
            enospc_error = OSError(errno.ENOSPC, "no space after partial write")
            write_attempts = 0

            def partial_then_enospc(descriptor: int, data: bytes) -> int:
                nonlocal write_attempts
                write_attempts += 1
                if write_attempts == 1:
                    return real_write(descriptor, data[:7])
                raise enospc_error

            with mock.patch(
                "idb.common.companion_set.os.write",
                side_effect=partial_then_enospc,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(enospc_state).add_companion(expected[0])
            self.assertIs(raised.exception, enospc_error)
            self.assertEqual(write_attempts, 2)
            self.assertEqual(enospc_state.read_bytes(), b"[]")
            self.assertEqual(_registry_artifacts(enospc_state), [])

            fsync_state = root / "fsync-state"
            fsync_state.write_bytes(b"[]")
            fsync_error = OSError(errno.EIO, "fsync failed")
            with (
                mock.patch(
                    "idb.common.companion_set.os.fsync",
                    side_effect=fsync_error,
                ),
                mock.patch(
                    "idb.common.companion_set.os.replace"
                ) as replace_after_fsync,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(fsync_state).add_companion(expected[0])
            self.assertIs(raised.exception, fsync_error)
            replace_after_fsync.assert_not_called()
            self.assertEqual(fsync_state.read_bytes(), b"[]")
            self.assertEqual(_registry_artifacts(fsync_state), [])

            directory_fsync_state = root / "directory-fsync-state"
            directory_fsync_state.write_bytes(b"[]")
            directory_fsync_error = OSError(errno.EIO, "directory fsync failed")
            fsync_calls = 0
            real_fsync = os.fsync

            def file_then_directory_fsync(descriptor: int) -> None:
                nonlocal fsync_calls
                fsync_calls += 1
                if fsync_calls == 2:
                    raise directory_fsync_error
                real_fsync(descriptor)

            with mock.patch(
                "idb.common.companion_set.os.fsync",
                side_effect=file_then_directory_fsync,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(directory_fsync_state).add_companion(expected[0])
            self.assertIs(raised.exception, directory_fsync_error)
            self.assertEqual(fsync_calls, 2)
            self.assertEqual(directory_fsync_state.read_bytes(), _ALPHA_STATE_BYTES)
            self.assertEqual(_registry_artifacts(directory_fsync_state), [])

            close_state = root / "close-state"
            close_state.write_bytes(b"[]")
            close_error = OSError(errno.EIO, "close failed")
            close_calls = 0
            real_close = os.close

            def close_then_fail(descriptor: int) -> None:
                nonlocal close_calls
                real_close(descriptor)
                close_calls += 1
                if close_calls == 1:
                    raise close_error

            with (
                mock.patch(
                    "idb.common.companion_set.os.close",
                    side_effect=close_then_fail,
                ),
                mock.patch(
                    "idb.common.companion_set.os.replace"
                ) as replace_after_close,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(close_state).add_companion(expected[0])
            self.assertIs(raised.exception, close_error)
            replace_after_close.assert_not_called()
            self.assertEqual(close_calls, 2)
            self.assertEqual(close_state.read_bytes(), b"[]")
            self.assertEqual(_registry_artifacts(close_state), [])

            replace_state = root / "replace-state"
            replace_state.write_bytes(b"[]")
            replace_error = OSError(errno.EACCES, "replace failed")
            with mock.patch(
                "idb.common.companion_set.os.replace",
                side_effect=replace_error,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(replace_state).add_companion(expected[0])
            self.assertIs(raised.exception, replace_error)
            self.assertEqual(replace_state.read_bytes(), b"[]")
            self.assertEqual(_registry_artifacts(replace_state), [])

            committed_state = root / "committed-state"
            committed_state.write_bytes(b"[]")
            post_commit_error = OSError(errno.EIO, "replace committed")

            def replace_then_fail(source: str, destination: str) -> None:
                real_replace(source, destination)
                raise post_commit_error

            with mock.patch(
                "idb.common.companion_set.os.replace",
                side_effect=replace_then_fail,
            ):
                with self.assertRaises(OSError) as raised:
                    await _manager(committed_state).add_companion(expected[0])
            self.assertIs(raised.exception, post_commit_error)
            self.assertEqual(committed_state.read_bytes(), _ALPHA_STATE_BYTES)
            self.assertEqual(_registry_artifacts(committed_state), [])

            serialization_state = root / "serialization-state"
            serialization_error = TypeError("serialization failed")
            with (
                mock.patch(
                    "idb.common.companion_set.json.dumps",
                    side_effect=serialization_error,
                ),
                mock.patch(
                    "idb.common.companion_set.tempfile.mkstemp"
                ) as make_temporary,
            ):
                with self.assertRaises(TypeError) as raised:
                    await _manager(serialization_state).add_companion(expected[0])
            self.assertIs(raised.exception, serialization_error)
            make_temporary.assert_not_called()
            self.assertFalse(serialization_state.exists())
            self.assertEqual(_registry_artifacts(serialization_state), [])
            self.assertEqual(_PENDING_CORRECTIONS["atomic_publication"], "landed")

    async def test_lock_contention_timeout_ownership_and_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            lock = Path(f"{state}.lock")

            async with _open_lockfile(str(state)):
                self.assertTrue(lock.exists())
            self.assertFalse(lock.exists())

            attempts = 0
            real_open = os.open

            def collide_once(path: str, flags: int) -> int:
                nonlocal attempts
                attempts += 1
                if attempts == 1:
                    raise FileExistsError(path)
                return real_open(path, flags)

            retry_sleep = mock.AsyncMock()
            with (
                mock.patch(
                    "idb.common.companion_set.os.open",
                    side_effect=collide_once,
                ),
                mock.patch(
                    "idb.common.companion_set.asyncio.sleep",
                    new=retry_sleep,
                ),
            ):
                async with _open_lockfile(str(state)):
                    self.assertTrue(lock.exists())
            self.assertEqual(attempts, 2)
            retry_sleep.assert_awaited_once_with(0.05)
            self.assertFalse(lock.exists())

            acquisition_error = PermissionError("lock acquisition failed")
            acquisition_sleep = mock.AsyncMock()
            with (
                mock.patch(
                    "idb.common.companion_set.os.open",
                    side_effect=acquisition_error,
                ),
                mock.patch(
                    "idb.common.companion_set.asyncio.sleep",
                    new=acquisition_sleep,
                ),
            ):
                with self.assertRaises(PermissionError) as raised:
                    async with _open_lockfile(str(state)):
                        self.fail("an acquisition error yielded the lock")
            self.assertIs(raised.exception, acquisition_error)
            acquisition_sleep.assert_not_awaited()
            self.assertFalse(lock.exists())

            lock.write_text("stale-owner")
            now = datetime.now()
            with mock.patch("idb.common.companion_set.datetime") as mocked_datetime:
                mocked_datetime.now.side_effect = [
                    now,
                    now + timedelta(seconds=4),
                ]
                with self.assertRaisesRegex(IdbException, "Failed to open"):
                    async with _open_lockfile(str(state)):
                        self.fail("a contending process acquired the stale lock")
            self.assertEqual(lock.read_text(), "stale-owner")
            lock.unlink()

            context = multiprocessing.get_context("spawn")
            ready = context.Event()
            release = context.Event()
            process = context.Process(
                target=_hold_lock_in_process,
                args=(str(state), ready, release),
            )
            process.start()
            try:
                self.assertTrue(await asyncio.to_thread(ready.wait, 10))
                self.assertTrue(lock.exists())
                now = datetime.now()
                with mock.patch("idb.common.companion_set.datetime") as mocked_datetime:
                    mocked_datetime.now.side_effect = [
                        now,
                        now + timedelta(seconds=4),
                    ]
                    with self.assertRaisesRegex(IdbException, "Failed to open"):
                        async with _open_lockfile(str(state)):
                            self.fail("a contender acquired another process's lock")
                self.assertTrue(lock.exists())
                self.assertTrue(process.is_alive())
            finally:
                release.set()
                await asyncio.to_thread(process.join, 10)
                if process.is_alive():
                    process.terminate()
                    await asyncio.to_thread(process.join, 10)
            exit_code = process.exitcode
            process.close()
            self.assertEqual(exit_code, 0)
            self.assertFalse(lock.exists())

            body_error = FileExistsError("raised by lock body")
            body_sleep = mock.AsyncMock()
            with mock.patch(
                "idb.common.companion_set.asyncio.sleep",
                new=body_sleep,
            ):
                with self.assertRaises(FileExistsError) as raised:
                    async with _open_lockfile(str(state)):
                        raise body_error
            self.assertIs(raised.exception, body_error)
            body_sleep.assert_not_awaited()
            self.assertFalse(lock.exists())
            self.assertEqual(
                {
                    name: _PENDING_CORRECTIONS[name]
                    for name in (
                        "lock_owner_only_cleanup",
                        "lock_body_file_exists_error_propagation",
                    )
                },
                {
                    "lock_owner_only_cleanup": "landed",
                    "lock_body_file_exists_error_propagation": "landed",
                },
            )

    async def test_python_write_rust_read_and_rust_write_python_read(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            expected = _companions()

            python_writer_fixture = root / "python-writer-state"
            python_writer = _manager(python_writer_fixture)
            await python_writer.add_companion(expected[1])
            await python_writer.add_companion(expected[0])
            self.assertEqual(python_writer_fixture.read_bytes(), _CURRENT_STATE_BYTES)

            python_reader_fixture = root / "python-reader-state"
            python_reader_fixture.write_bytes(_CURRENT_STATE_BYTES)
            self.assertEqual(
                await _manager(python_reader_fixture).get_companions(), expected
            )
            self.assertEqual(python_reader_fixture.read_bytes(), _CURRENT_STATE_BYTES)
            self.assertEqual(
                {
                    name: _PENDING_RUST_HALVES[name]
                    for name in (
                        "rust_reads_python_state",
                        "rust_writes_python_state",
                    )
                },
                {
                    "rust_reads_python_state": "pending",
                    "rust_writes_python_state": "pending",
                },
            )
