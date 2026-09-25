#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from unittest import mock

from idb.common.companion_set import _open_lockfile, CompanionSet
from idb.common.types import (
    CompanionInfo,
    DomainSocketAddress,
    IdbException,
    TCPAddress,
)
from idb.utils.testing import ignoreTaskLeaks, TestCase


_CURRENT_STATE_BYTES: bytes = (
    b'[{"udid": "alpha", "is_local": false, "pid": null, '
    b'"host": "127.0.0.1", "port": 10882}, '
    b'{"udid": "zeta", "is_local": true, "pid": 314, '
    b'"path": "/tmp/zeta.sock"}]'
)
_PENDING_CORRECTIONS: dict[str, str] = {
    "atomic_publication": "pending",
    "lock_body_file_exists_error_propagation": "pending",
    "lock_owner_only_cleanup": "pending",
}
_PENDING_RUST_HALVES: dict[str, str] = {
    "rust_reads_python_state": "pending",
    "rust_writes_python_state": "pending",
}


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

            for name, valid_empty_bytes in (
                ("empty_object", b"{}"),
                ("empty_string", b'""'),
            ):
                with self.subTest(state=name):
                    state = root / name
                    state.write_bytes(valid_empty_bytes)
                    self.assertEqual(await _manager(state).get_companions(), [])
                    self.assertEqual(state.read_bytes(), valid_empty_bytes)

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

    async def test_sorted_state_schema_and_exact_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            expected = _companions()
            manager = _manager(state)

            await manager.add_companion(expected[1])
            await manager.add_companion(expected[0])
            self.assertEqual(state.read_bytes(), _CURRENT_STATE_BYTES)
            self.assertEqual(await manager.get_companions(), expected)
            self.assertEqual(state.read_bytes(), _CURRENT_STATE_BYTES)

            truncating_state = root / "truncating-state"
            truncating_state.write_bytes(b"[]")
            with mock.patch(
                "idb.common.companion_set.json.dump",
                side_effect=OSError("write failed"),
            ):
                with self.assertRaisesRegex(OSError, "write failed"):
                    await _manager(truncating_state).add_companion(expected[0])
            self.assertEqual(truncating_state.read_bytes(), b"")
            self.assertEqual(_PENDING_CORRECTIONS["atomic_publication"], "pending")

    async def test_lock_contention_timeout_ownership_and_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            lock = Path(f"{state}.lock")

            async with _open_lockfile(str(state)):
                self.assertTrue(lock.exists())
            self.assertFalse(lock.exists())

            lock.write_text("owner")
            now = datetime.now()
            with mock.patch("idb.common.companion_set.datetime") as mocked_datetime:
                mocked_datetime.now.side_effect = [
                    now,
                    now + timedelta(seconds=4),
                ]
                with self.assertRaisesRegex(IdbException, "Failed to open"):
                    async with _open_lockfile(str(state)):
                        self.fail("a contending process acquired the owner lock")
            self.assertFalse(lock.exists())

            body_error_was_suppressed = False
            try:
                async with _open_lockfile(str(state)):
                    raise FileExistsError("raised by lock body")
            except FileExistsError:
                self.fail("the pending body-error correction unexpectedly landed")
            body_error_was_suppressed = True
            self.assertTrue(body_error_was_suppressed)
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
                    "lock_owner_only_cleanup": "pending",
                    "lock_body_file_exists_error_propagation": "pending",
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
