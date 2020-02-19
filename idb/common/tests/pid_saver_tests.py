#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
import signal
import tempfile
from unittest import mock

from idb.common.pid_saver import PidSaver
from idb.utils.testing import TestCase, ignoreTaskLeaks


@ignoreTaskLeaks
class PidSaverTests(TestCase):
    def test_save_companion_pid(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            pid_saver = PidSaver(logger=mock.MagicMock(), pids_file_path=f.name)
            pid = 1
            pid_saver.save_companion_pid(pid)
            data = json.load(f)
            companion_pids = data["companions"]
            self.assertEqual(companion_pids[0], pid)

    def test_save_notifier_pid(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            pid_saver = PidSaver(logger=mock.MagicMock(), pids_file_path=f.name)
            pid = 1
            pid_saver.save_notifier_pid(pid)
            data = json.load(f)
            notifier_pid = data["notifier"]
            self.assertEqual(notifier_pid, pid)

    def test_get_saved_pids(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            pid_saver = PidSaver(logger=mock.MagicMock(), pids_file_path=f.name)
            companion_pids = [1, 2]
            notifier_pid = 3
            with open(f.name, "w") as f:
                json.dump(({"companions": companion_pids, "notifier": notifier_pid}), f)
            pid_saver._load()
            self.assertEqual(pid_saver.companion_pids, companion_pids)
            self.assertEqual(pid_saver.notifier_pid, notifier_pid)

    def test_clear(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            pid_saver = PidSaver(logger=mock.MagicMock(), pids_file_path=f.name)
            pid = 1
            pid_saver.save_companion_pid(pid)
            pid_saver._clear_saved_pids()
            pid_saver._load()
            self.assertEqual(pid_saver.companion_pids, [])
            self.assertEqual(pid_saver.notifier_pid, 0)

    async def test_kill_saved_pids(self) -> None:
        with tempfile.NamedTemporaryFile() as f:
            pid_saver = PidSaver(logger=mock.MagicMock(), pids_file_path=f.name)
            companion_pid = 1
            pid_saver.save_companion_pid(companion_pid)
            notifier_pid = 2
            pid_saver.save_notifier_pid(notifier_pid)
            with mock.patch("idb.common.pid_saver.os.kill") as kill:
                pid_saver.kill_saved_pids()
                kill.assert_has_calls(
                    [mock.call(1, signal.SIGTERM), mock.call(2, signal.SIGTERM)]
                )
