#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import os
import sys
from argparse import Namespace
from typing import Any, Optional, Tuple, TypeVar
from unittest.mock import ANY, MagicMock, patch

from idb.cli.main import gen_main as cli_main
from idb.common.types import (
    CrashLogQuery,
    DomainSocketAddress,
    HIDButtonType,
    InstrumentsTimings,
    Permission,
    TCPAddress,
)
from idb.utils.testing import AsyncContextManagerMock, AsyncMock, TestCase


T = TypeVar("T")
COMPANION_PATH: Optional[str] = (
    "/usr/local/bin/idb_companion" if sys.platform == "darwin" else None
)


class AsyncGeneratorMock(AsyncMock):
    def __call__(self) -> None:
        super()

    def __init__(self, iter_list: Tuple[T, ...] = ()) -> None:
        super().__init__()
        self.iter_list = iter_list
        self.iter_pos: int = -1

    def __aiter__(self) -> AsyncMock:
        self.iter_pos = -1
        return self

    async def __anext__(self) -> MagicMock:
        try:
            self.iter_pos += 1
            return self.iter_list[self.iter_pos]
        except IndexError:
            raise StopAsyncIteration()


class TestParser(TestCase):
    def __init__(self, *args: Any, **kws: Any) -> None:
        super().__init__(*args, loop=asyncio.get_event_loop(), **kws)

    def setUp(self) -> None:
        self.client_mock = MagicMock(name="client_mock")
        self.client_mock.build.return_value = AsyncContextManagerMock(
            return_value=self.client_mock
        )
        self.client_manager_mock = MagicMock(name="client_manager_mock")
        self.client_manager_mock().from_udid.return_value = AsyncContextManagerMock(
            return_value=self.client_mock
        )
        self.client_manager_patch = patch(
            "idb.cli.ClientManager", self.client_manager_mock
        )
        self.client_manager_patch.start()
        self.client_patch = patch("idb.cli.GrpcClient", self.client_mock)
        self.client_patch.start()
        self.companion_mock = MagicMock(name="companion_mock")
        self.companion_patch = patch("idb.cli.LocalCompanion", self.companion_mock)
        self.companion_patch.start()

    def tearDown(self) -> None:
        self.client_manager_patch.stop()
        self.client_patch.stop()
        self.companion_patch.stop()

    async def test_launch_with_udid(self) -> None:
        bundle_id = "com.foo.app"
        udid = "my udid"
        self.client_mock.launch = AsyncMock(return_value=bundle_id)
        await cli_main(cmd_input=["launch", "--udid", udid, bundle_id])
        self.client_mock.launch.assert_called_once_with(
            bundle_id=bundle_id,
            env={},
            args=[],
            foreground_if_running=False,
            wait_for_debugger=False,
            stop=None,
        )

    async def test_create(self) -> None:
        await cli_main(
            cmd_input=["--companion-path", "idb_companion", "create", "ipone", "os2"]
        )
        self.companion_mock().create.assert_called_once_with(
            device_type="ipone", os_version="os2"
        )

    async def test_boot(self) -> None:
        for command in [
            ["--companion-path", "idb_companion", "boot", "my_udid"],
            ["--companion-path", "idb_companion", "boot", "--udid", "my_udid"],
            [
                "--companion-path",
                "idb_companion",
                "boot",
                "--udid",
                "my_udid_old",
                "my_udid",
            ],
        ]:
            self.companion_mock().boot = AsyncMock()
            await cli_main(cmd_input=command)
            self.companion_mock().boot.assert_called_once_with(udid="my_udid")

    async def test_shutdown(self) -> None:
        udid = "my udid"
        await cli_main(
            cmd_input=["--companion-path", "idb_companion", "shutdown", udid]
        )
        self.companion_mock().shutdown.assert_called_once_with(udid=udid)

    async def test_erase(self) -> None:
        udid = "my udid"
        await cli_main(cmd_input=["--companion-path", "idb_companion", "erase", udid])
        self.companion_mock().erase.assert_called_once_with(udid=udid)

    async def test_clone(self) -> None:
        udid = "my udid"
        await cli_main(cmd_input=["--companion-path", "idb_companion", "clone", udid])
        self.companion_mock().clone.assert_called_once_with(udid=udid)

    async def test_delete(self) -> None:
        udid = "my udid"
        await cli_main(cmd_input=["--companion-path", "idb_companion", "delete", udid])
        self.companion_mock().delete.assert_called_once_with(udid=udid)

    async def test_delete_all(self) -> None:
        self.companion_mock().delete = AsyncMock()
        await cli_main(cmd_input=["--companion-path", "idb_companion", "delete-all"])
        self.companion_mock().delete.assert_called_once_with(udid=None)

    async def test_install(self) -> None:
        self.client_mock.install = MagicMock(return_value=AsyncGeneratorMock())
        app_path = "testApp.app"
        await cli_main(cmd_input=["install", app_path])
        self.client_mock.install.assert_called_once_with(app_path)

    async def test_uninstall(self) -> None:
        self.client_mock.uninstall = AsyncMock()
        app_path = "com.dummy.app"
        await cli_main(cmd_input=["uninstall", app_path])
        self.client_mock.uninstall.assert_called_once_with(bundle_id=app_path)

    async def test_list_apps(self) -> None:
        self.client_mock.list_apps = AsyncMock(return_value=[])
        await cli_main(cmd_input=["list-apps"])
        self.client_mock.list_apps.assert_called_once()

    async def test_list_apps_direct_companion_tcp(self) -> None:
        self.client_mock.list_apps = AsyncMock(return_value=[])
        await cli_main(cmd_input=["--companion", "thehost:123", "list-apps"])
        self.client_mock.list_apps.assert_called_once()
        self.client_mock.build.assert_called_once_with(
            address=TCPAddress(host="thehost", port=123), is_local=False, logger=ANY
        )

    async def test_list_apps_direct_companion_uxd(self) -> None:
        self.client_mock.list_apps = AsyncMock(return_value=[])
        await cli_main(cmd_input=["--companion", "/foo/sock", "list-apps"])
        self.client_mock.list_apps.assert_called_once()
        self.client_mock.build.assert_called_once_with(
            address=DomainSocketAddress(path="/foo/sock"), is_local=False, logger=ANY
        )

    async def test_connect_with_host_and_port(self) -> None:
        self.client_manager_mock().connect = AsyncMock()
        host = "someHost"
        port = 1234
        await cli_main(cmd_input=["connect", host, str(port)])
        self.client_manager_mock().connect.assert_called_once_with(
            destination=TCPAddress(host=host, port=port), metadata=ANY
        )

    async def test_connect_with_udid(self) -> None:
        self.client_manager_mock().connect = AsyncMock()
        udid = "0B3311FA-234C-4665-950F-37544F690B61"
        await cli_main(cmd_input=["connect", udid])
        self.client_manager_mock().connect.assert_called_once_with(
            destination=udid, metadata=ANY
        )

    async def test_disconnect_with_host_and_port(self) -> None:
        self.client_manager_mock().disconnect = AsyncMock()
        host = "someHost"
        port = 1234
        await cli_main(cmd_input=["disconnect", host, str(port)])
        self.client_manager_mock().disconnect.assert_called_once_with(
            destination=TCPAddress(host=host, port=port)
        )

    async def test_disconnect_with_udid(self) -> None:
        self.client_manager_mock().disconnect = AsyncMock()
        udid = "0B3311FA-234C-4665-950F-37544F690B61"
        await cli_main(cmd_input=["disconnect", udid])
        self.client_manager_mock().disconnect.assert_called_once_with(destination=udid)

    async def test_mkdir(self) -> None:
        self.client_mock.mkdir = AsyncMock()
        src = "path"
        cmd_input = ["file", "mkdir", src]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mkdir.assert_called_once_with(container=None, path=src)

    async def test_bundled_file_mkdir_flag(self) -> None:
        self.client_mock.mkdir = AsyncMock()
        src = "path"
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "mkdir", src, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mkdir.assert_called_once_with(container=bundle_id, path=src)

    async def test_bundled_file_mkdir_colon(self) -> None:
        self.client_mock.mkdir = AsyncMock()
        cmd_input = ["file", "mkdir", "com.bundle.id:path"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mkdir.assert_called_once_with(
            container="com.bundle.id", path="path"
        )

    async def test_rm(self) -> None:
        self.client_mock.rm = AsyncMock()
        src = "path"
        cmd_input = ["file", "remove", src]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.rm.assert_called_once_with(container=None, paths=[src])

    async def test_bundled_file_rmpath_flag(self) -> None:
        self.client_mock.rm = AsyncMock()
        src = "path"
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "remove", src, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.rm.assert_called_once_with(container=bundle_id, paths=[src])

    async def test_bundled_file_rmpath_flag_multiple(self) -> None:
        self.client_mock.rm = AsyncMock()
        srcs = ["pathA", "pathB"]
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "remove", srcs[0], srcs[1], "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.rm.assert_called_once_with(container=bundle_id, paths=srcs)

    async def test_bundled_file_rmpath_colon(self) -> None:
        self.client_mock.rm = AsyncMock()
        cmd_input = ["file", "remove", "com.bundle.id:path"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.rm.assert_called_once_with(
            container="com.bundle.id", paths=["path"]
        )

    async def test_list(self) -> None:
        self.client_mock.ls_single = AsyncMock(return_value=[])
        src = "path"
        cmd_input = ["file", "list", src]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.ls_single.assert_called_once_with(container=None, path=src)

    async def test_bundled_file_list_flag(self) -> None:
        self.client_mock.ls_single = AsyncMock(return_value=[])
        src = "path"
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "list", src, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.ls_single.assert_called_once_with(
            container=bundle_id, path=src
        )

    async def test_bundled_file_list_colon(self) -> None:
        self.client_mock.ls_single = AsyncMock(return_value=[])
        cmd_input = ["file", "list", "com.bundle.id:path"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.ls_single.assert_called_once_with(
            container="com.bundle.id", path="path"
        )

    async def test_file_move(self) -> None:
        self.client_mock.mv = AsyncMock(return_value=[])
        src = "a"
        dst = "b"
        cmd_input = ["file", "move", src, dst]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mv.assert_called_once_with(
            container=None, src_paths=[src], dest_path=dst
        )

    async def test_bundled_file_move_flag(self) -> None:
        self.client_mock.mv = AsyncMock(return_value=[])
        src = "a"
        dst = "b"
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "move", src, dst, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mv.assert_called_once_with(
            container=bundle_id, src_paths=[src], dest_path=dst
        )

    async def test_bundled_file_move_flag_multiple(self) -> None:
        self.client_mock.mv = AsyncMock(return_value=[])
        srcs = ["src1", "src2"]
        dst = "b"
        bundle_id = "com.bundle.id"
        cmd_input = ["file", "move", srcs[0], srcs[1], dst, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mv.assert_called_once_with(
            container=bundle_id, src_paths=srcs, dest_path=dst
        )

    async def test_bundled_file_move_colon(self) -> None:
        self.client_mock.mv = AsyncMock(return_value=[])
        src = "a"
        cmd_input = ["file", "move", src, "com.bundle.id:b"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.mv.assert_called_once_with(
            container="com.bundle.id", src_paths=[src], dest_path="b"
        )

    async def test_file_push(self) -> None:
        self.client_mock.push = AsyncMock()
        src = "Library/myFile.txt"
        dst = "someOutputDir"
        cmd_input = ["file", "push", src, dst]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.push.assert_called_once_with(
            container=None, src_paths=[os.path.abspath(src)], dest_path=dst
        )

    async def test_bundled_file_push_single_flag(self) -> None:
        self.client_mock.push = AsyncMock()
        bundle_id = "com.myapp"
        src = "Library/myFile.txt"
        dst = "someOutputDir"
        cmd_input = ["file", "push", src, dst, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.push.assert_called_once_with(
            container=bundle_id, src_paths=[os.path.abspath(src)], dest_path=dst
        )

    async def test_bundled_file_push_multi_flag(self) -> None:
        self.client_mock.push = AsyncMock(return_value=[])
        bundle_id = "com.myapp"
        src1 = "Library/myFile.txt"
        src2 = "Library/myFile2.txt"
        dst = "someOutputDir"
        cmd_input = ["file", "push", src1, src2, dst, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.push.assert_called_once_with(
            container=bundle_id,
            src_paths=[os.path.abspath(path) for path in [src1, src2]],
            dest_path=dst,
        )

    async def test_bundled_file_push_single_colon(self) -> None:
        self.client_mock.push = AsyncMock(return_value=[])
        src = "Library/myFile.txt"
        cmd_input = ["file", "push", src, "com.bundle.id:someOutputDir"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.push.assert_called_once_with(
            container="com.bundle.id",
            src_paths=[os.path.abspath(src)],
            dest_path="someOutputDir",
        )

    async def test_bundled_file_push_multi_colon(self) -> None:
        self.client_mock.push = AsyncMock(return_value=[])
        src1 = "Library/myFile.txt"
        src2 = "Library/myFile2.txt"
        cmd_input = ["file", "push", src1, src2, "com.bundle.id:someOutputDir"]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.push.assert_called_once_with(
            container="com.bundle.id",
            src_paths=[os.path.abspath(path) for path in [src1, src2]],
            dest_path="someOutputDir",
        )

    async def test_file_pull(self) -> None:
        self.client_mock.pull = AsyncMock(return_value=[])
        src = "Library/myFile.txt"
        dst = "someOutputDir"
        cmd_input = ["file", "pull", src, dst]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.pull.assert_called_once_with(
            container=None, src_path=src, dest_path=os.path.abspath(dst)
        )

    async def test_bundled_file_pull(self) -> None:
        self.client_mock.pull = AsyncMock(return_value=[])
        bundle_id = "com.myapp"
        src = "Library/myFile.txt"
        dst = "someOutputDir"
        cmd_input = ["file", "pull", src, dst, "--bundle-id", bundle_id]
        await cli_main(cmd_input=cmd_input)
        self.client_mock.pull.assert_called_once_with(
            container=bundle_id, src_path=src, dest_path=os.path.abspath(dst)
        )

    async def test_list_targets(self) -> None:
        self.client_manager_mock().list_targets = AsyncMock(return_value=[])
        await cli_main(cmd_input=["list-targets"])
        self.client_manager_mock().list_targets.assert_called_once()

    async def test_kill(self) -> None:
        self.client_manager_mock().kill = AsyncMock(return_value=[])
        await cli_main(cmd_input=["kill"])
        self.client_manager_mock().kill.assert_called_once_with()

    async def test_xctest_install(self) -> None:
        self.client_mock.install_xctest = MagicMock(return_value=AsyncGeneratorMock())
        test_bundle_path = "testBundle.xctest"
        await cli_main(cmd_input=["xctest", "install", test_bundle_path])
        self.client_mock.install_xctest.assert_called_once_with(test_bundle_path)

    def xctest_run_namespace(self, command: str, test_bundle_id: str) -> Namespace:
        namespace = Namespace()
        namespace.companion_path = COMPANION_PATH
        namespace.companion = None
        namespace.companion_local = False
        namespace.prune_dead_companion = True
        namespace.log_level = "WARNING"
        namespace.log_level_deprecated = None
        namespace.root_command = "xctest"
        namespace.xctest = "run"
        namespace.udid = None
        namespace.json = False
        if command in ["app", "ui"]:
            namespace.tests_to_run = None
            namespace.tests_to_skip = None
            namespace.test_arguments = []
        elif command == "logic":
            namespace.test_to_run = None
            namespace.tests_to_run = None
        namespace.run = command
        namespace.test_bundle_id = test_bundle_id
        namespace.result_bundle_path = None
        namespace.report_activities = False
        namespace.report_attachments = False
        namespace.activities_output_path = None
        namespace.coverage_output_path = None
        namespace.install = False
        return namespace

    async def test_xctest_run_app(self) -> None:
        mock = AsyncMock()
        mock.return_value = []
        with patch(
            "idb.cli.commands.xctest.XctestRunAppCommand.run", new=mock, create=True
        ):
            test_bundle_id = "com.me.tests"
            app_under_test_id = "com.me.app"
            await cli_main(
                cmd_input=["xctest", "run", "app", test_bundle_id, app_under_test_id]
            )
            namespace = self.xctest_run_namespace("app", test_bundle_id)
            namespace.app_bundle_id = app_under_test_id
            namespace.timeout = None
            mock.assert_called_once_with(namespace)

    async def test_xctest_run_ui(self) -> None:
        mock = AsyncMock()
        mock.return_value = []
        with patch(
            "idb.cli.commands.xctest.XctestRunUICommand.run", new=mock, create=True
        ):
            test_bundle_id = "com.me.tests"
            app_under_test_id = "com.me.app"
            test_host_app_bundle_id = "com.host.app"
            await cli_main(
                cmd_input=[
                    "xctest",
                    "run",
                    "ui",
                    test_bundle_id,
                    app_under_test_id,
                    test_host_app_bundle_id,
                ]
            )
            namespace = self.xctest_run_namespace("ui", test_bundle_id)
            namespace.app_bundle_id = app_under_test_id
            namespace.test_host_app_bundle_id = test_host_app_bundle_id
            namespace.timeout = None
            mock.assert_called_once_with(namespace)

    async def test_xctest_run_logic(self) -> None:
        mock = AsyncMock()
        mock.return_value = []
        with patch(
            "idb.cli.commands.xctest.CommonRunXcTestCommand.run", new=mock, create=True
        ):
            test_bundle_id = "com.me.tests"
            await cli_main(cmd_input=["xctest", "run", "logic", test_bundle_id])
            namespace = self.xctest_run_namespace("logic", test_bundle_id)
            namespace.timeout = None
            mock.assert_called_once_with(namespace)

    async def test_xctest_list(self) -> None:
        self.client_mock.list_xctests = AsyncMock(return_value=[])
        await cli_main(cmd_input=["xctest", "list"])
        self.client_mock.list_xctests.assert_called_once()

    async def test_xctest_list_bundles(self) -> None:
        self.client_mock.list_test_bundle = AsyncMock(return_value=[])
        bundle_id = "myBundleID"
        await cli_main(cmd_input=["xctest", "list-bundle", bundle_id])
        self.client_mock.list_test_bundle.assert_called_once_with(
            test_bundle_id=bundle_id, app_path=None
        )

    async def test_daemon(self) -> None:
        mock = AsyncMock()
        with patch(
            "idb.cli.commands.daemon.DaemonCommand._run_impl", new=mock, create=True
        ):
            port = 9888
            grpc_port = 1235
            await cli_main(cmd_input=["daemon", "--daemon-grpc-port", str(grpc_port)])
            namespace = Namespace()
            namespace.companion_path = COMPANION_PATH
            namespace.companion = None
            namespace.companion_local = False
            namespace.prune_dead_companion = True
            namespace.daemon_port = port
            namespace.daemon_grpc_port = grpc_port
            namespace.log_level = "WARNING"
            namespace.log_level_deprecated = None
            namespace.root_command = "daemon"
            namespace.json = False
            namespace.reply_fd = None
            namespace.prefer_ipv6 = False
            namespace.notifier_path = None
            mock.assert_called_once_with(namespace)

    async def test_terminate(self) -> None:
        self.client_mock.terminate = AsyncMock(return_value=[])
        bundle_id = "com.foo.app"
        udid = "my udid"
        await cli_main(cmd_input=["terminate", bundle_id, "--udid", udid])
        self.client_mock.terminate.assert_called_once_with(bundle_id)

    async def test_log(self) -> None:
        mock = AsyncMock()
        with patch("idb.cli.commands.log.LogCommand._run_impl", new=mock, create=True):
            await cli_main(cmd_input=["log", "--udid", "1234"])
            namespace = Namespace()
            namespace.companion_path = COMPANION_PATH
            namespace.companion = None
            namespace.companion_local = False
            namespace.prune_dead_companion = True
            namespace.log_level = "WARNING"
            namespace.log_level_deprecated = None
            namespace.root_command = "log"
            namespace.udid = "1234"
            namespace.json = False
            namespace.log_arguments = []
            mock.assert_called_once_with(namespace)

    async def test_log_arguments(self) -> None:
        mock = AsyncMock()
        with patch("idb.cli.commands.log.LogCommand._run_impl", new=mock, create=True):
            await cli_main(cmd_input=["log", "--", "--style", "json"])
            namespace = Namespace()
            namespace.companion_path = COMPANION_PATH
            namespace.companion = None
            namespace.companion_local = False
            namespace.prune_dead_companion = True
            namespace.log_level = "WARNING"
            namespace.log_level_deprecated = None
            namespace.root_command = "log"
            namespace.udid = None
            namespace.json = False
            namespace.log_arguments = ["--", "--style", "json"]
            mock.assert_called_once_with(namespace)

    async def test_clear_keychain(self) -> None:
        self.client_mock.clear_keychain = AsyncMock(return_value=[])
        await cli_main(cmd_input=["clear-keychain"])
        self.client_mock.clear_keychain.assert_called_once()

    async def test_open_url(self) -> None:
        self.client_mock.open_url = AsyncMock(return_value=[])
        url = "http://facebook.com"
        await cli_main(cmd_input=["open", url])
        self.client_mock.open_url.assert_called_once_with(url)

    async def test_set_location(self) -> None:
        self.client_mock.set_location = AsyncMock(return_value=[])
        latitude = 1.0
        longitude = 2.0
        await cli_main(cmd_input=["set-location", str(latitude), str(longitude)])
        self.client_mock.set_location.assert_called_once_with(latitude, longitude)

    async def test_approve(self) -> None:
        self.client_mock.approve = AsyncMock(return_value=[])
        bundle_id = "com.fb.myApp"
        await cli_main(cmd_input=["approve", bundle_id, "photos"])
        self.client_mock.approve.assert_called_once_with(
            bundle_id=bundle_id, permissions={Permission.PHOTOS}, scheme=None
        )

    async def test_approve_url(self) -> None:
        self.client_mock.approve = AsyncMock(return_value=[])
        bundle_id = "com.fb.myApp"
        await cli_main(cmd_input=["approve", bundle_id, "url", "--scheme", "fb"])
        self.client_mock.approve.assert_called_once_with(
            bundle_id=bundle_id, permissions={Permission.URL}, scheme="fb"
        )

    async def test_video_record(self) -> None:
        mock = AsyncMock()
        with patch(
            "idb.cli.commands.video.VideoRecordCommand._run_impl", new=mock, create=True
        ):
            output_file = "video.mp4"
            await cli_main(cmd_input=["record-video", output_file])
            namespace = Namespace()
            namespace.companion_path = COMPANION_PATH
            namespace.companion = None
            namespace.companion_local = False
            namespace.prune_dead_companion = True
            namespace.log_level = "WARNING"
            namespace.log_level_deprecated = None
            namespace.root_command = "record-video"
            namespace.udid = None
            namespace.json = False
            namespace.output_file = output_file
            mock.assert_called_once_with(namespace)

    async def test_video_stream(self) -> None:
        mock = AsyncMock()
        with patch(
            "idb.cli.commands.video.VideoStreamCommand._run_impl", new=mock, create=True
        ):
            output_file = "video.mp4"
            await cli_main(cmd_input=["video-stream", output_file])
            mock.assert_called_once_with(
                Namespace(
                    companion=None,
                    companion_path=COMPANION_PATH,
                    companion_local=False,
                    prune_dead_companion=True,
                    log_level="WARNING",
                    format="h264",
                    fps=None,
                    log_level_deprecated=None,
                    compression_quality=0.2,
                    scale_factor=1,
                    root_command="video-stream",
                    udid=None,
                    json=False,
                    output_file=output_file,
                )
            )

    async def test_key_sequence(self) -> None:
        self.client_mock.key_sequence = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "key-sequence", "1", "2", "3"])
        self.client_mock.key_sequence.assert_called_once_with(key_sequence=[1, 2, 3])

    async def test_tap(self) -> None:
        self.client_mock.tap = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "tap", "10", "20"])
        self.client_mock.tap.assert_called_once_with(x=10, y=20, duration=None)

    async def test_button(self) -> None:
        self.client_mock.button = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "button", "SIRI"])
        self.client_mock.button.assert_called_once_with(
            button_type=HIDButtonType.SIRI, duration=None
        )

    async def test_key(self) -> None:
        self.client_mock.key = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "key", "12"])
        self.client_mock.key.assert_called_once_with(keycode=12, duration=None)

    async def test_text_input(self) -> None:
        self.client_mock.text = AsyncMock(return_value=[])
        text = "Some Text"
        await cli_main(cmd_input=["ui", "text", text])
        self.client_mock.text.assert_called_once_with(text=text)

    async def test_swipe_with_delta(self) -> None:
        self.client_mock.swipe = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "swipe", "1", "2", "3", "4", "--delta", "5"])
        self.client_mock.swipe.assert_called_once_with(
            p_start=(1, 2), p_end=(3, 4), duration=None, delta=5
        )

    async def test_swipe_with_duration(self) -> None:
        self.client_mock.swipe = AsyncMock(return_value=[])
        await cli_main(
            cmd_input=["ui", "swipe", "1", "2", "3", "4", "--duration", "0.5"]
        )
        self.client_mock.swipe.assert_called_once_with(
            p_start=(1, 2), p_end=(3, 4), duration=0.5, delta=None
        )

    async def test_swipe_without_extra_params(self) -> None:
        self.client_mock.swipe = AsyncMock(return_value=[])
        await cli_main(cmd_input=["ui", "swipe", "1", "2", "3", "4"])
        self.client_mock.swipe.assert_called_once_with(
            p_start=(1, 2), p_end=(3, 4), duration=None, delta=None
        )

    async def test_contacts_update(self) -> None:
        self.client_mock.contacts_update = AsyncMock(return_value=[])
        await cli_main(cmd_input=["contacts", "update", "/dev/null"])
        self.client_mock.contacts_update.assert_called_once_with(
            contacts_path="/dev/null"
        )

    async def test_accessibility_info_all(self) -> None:
        self.client_mock.accessibility_info = AsyncMock()
        await cli_main(cmd_input=["ui", "describe-all"])
        self.client_mock.accessibility_info.assert_called_once_with(
            point=None, nested=False
        )

    async def test_accessibility_info_all_nested(self) -> None:
        self.client_mock.accessibility_info = AsyncMock()
        await cli_main(cmd_input=["ui", "describe-all", "--nested"])
        self.client_mock.accessibility_info.assert_called_once_with(
            point=None, nested=True
        )

    async def test_accessibility_info_at_point(self) -> None:
        self.client_mock.accessibility_info = AsyncMock()
        await cli_main(cmd_input=["ui", "describe-point", "10", "20"])
        self.client_mock.accessibility_info.assert_called_once_with(
            point=(10, 20), nested=False
        )

    async def test_accessibility_info_at_point(self) -> None:
        self.client_mock.accessibility_info = AsyncMock()
        await cli_main(cmd_input=["ui", "describe-point", "--nested", "10", "20"])
        self.client_mock.accessibility_info.assert_called_once_with(
            point=(10, 20), nested=True
        )

    async def test_crash_list_all(self) -> None:
        self.client_mock.crash_list = AsyncMock(return_value=[])
        await cli_main(cmd_input=["crash", "list"])
        self.client_mock.crash_list.assert_called_once_with(query=CrashLogQuery())

    async def test_crash_list_with_predicate(self) -> None:
        self.client_mock.crash_list = AsyncMock(return_value=[])
        await cli_main(cmd_input=["crash", "list", "--since", "20"])
        self.client_mock.crash_list.assert_called_once_with(
            query=CrashLogQuery(since=20)
        )

    async def test_crash_show(self) -> None:
        self.client_mock.crash_show = AsyncMock()
        await cli_main(cmd_input=["crash", "show", "foo"])
        self.client_mock.crash_show.assert_called_once_with(name="foo")

    async def test_crash_delete_all(self) -> None:
        self.client_mock.crash_delete = AsyncMock(return_value=[])
        await cli_main(cmd_input=["crash", "delete", "--all"])
        self.client_mock.crash_delete.assert_called_once_with(query=CrashLogQuery())

    async def test_crash_delete_with_predicate(self) -> None:
        self.client_mock.crash_delete = AsyncMock(return_value=[])
        await cli_main(cmd_input=["crash", "delete", "--since", "20"])
        self.client_mock.crash_delete.assert_called_once_with(
            query=CrashLogQuery(since=20)
        )

    async def test_crash_delete_with_name(self) -> None:
        self.client_mock.crash_delete = AsyncMock(return_value=[])
        await cli_main(cmd_input=["crash", "delete", "some.foo.bar.crash"])
        self.client_mock.crash_delete.assert_called_once_with(
            query=CrashLogQuery(name="some.foo.bar.crash")
        )

    async def test_instruments(self) -> None:
        self.client_mock.run_instruments = AsyncMock()
        template_name = "System Trace"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "instruments",
                "--output",
                trace_path,
                "--template",
                template_name,
            ]
        )
        self.client_mock.run_instruments.assert_called_once_with(
            stop=ANY,
            trace_basename="trace",
            template_name=template_name,
            app_bundle_id=None,
            app_environment={},
            app_arguments=[],
            tool_arguments=None,
            timings=None,
            post_process_arguments=[],
        )

    async def test_instruments_with_post_args(self) -> None:
        self.client_mock.run_instruments = AsyncMock()
        template_name = "Time Profiler"
        trace_path = "trace.trace"
        post_process_arguments = ["instrumental", "convert"]
        await cli_main(
            cmd_input=[
                "instruments",
                "--output",
                trace_path,
                "--template",
                template_name,
                "--post-args",
                *post_process_arguments,
            ]
        )
        self.client_mock.run_instruments.assert_called_once_with(
            stop=ANY,
            trace_basename="trace",
            template_name=template_name,
            app_bundle_id=None,
            app_environment={},
            app_arguments=[],
            tool_arguments=None,
            timings=None,
            post_process_arguments=post_process_arguments,
        )

    async def test_instruments_with_app_args(self) -> None:
        self.client_mock.run_instruments = AsyncMock()
        template_name = "System Trace"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "instruments",
                "--output",
                trace_path,
                "--template",
                template_name,
                "--app-args",
                "perfLab",
            ]
        )
        self.client_mock.run_instruments.assert_called_once_with(
            stop=ANY,
            trace_basename="trace",
            template_name=template_name,
            app_bundle_id=None,
            app_environment={},
            app_arguments=["perfLab"],
            tool_arguments=None,
            timings=None,
            post_process_arguments=[],
        )

    async def test_instruments_with_all_timings(self) -> None:
        self.client_mock.run_instruments = AsyncMock()
        template_name = "System Trace"
        trace_path = "trace.trace"
        (
            launch_error_timeout,
            launch_retry_timeout,
            terminate_timeout,
            operation_duration,
        ) = ("10.0", "200.0", "200.0", "30")
        await cli_main(
            cmd_input=[
                "instruments",
                "--output",
                trace_path,
                "--template",
                template_name,
                "--app-args",
                "perfLab",
                "--operation-duration",
                operation_duration,
                "--launch-retry-timeout",
                launch_retry_timeout,
                "--terminate-timeout",
                terminate_timeout,
                "--launch-error-timeout",
                launch_error_timeout,
            ]
        )
        self.client_mock.run_instruments.assert_called_once_with(
            stop=ANY,
            trace_basename="trace",
            template_name=template_name,
            app_bundle_id=None,
            app_environment={},
            app_arguments=["perfLab"],
            tool_arguments=None,
            timings=InstrumentsTimings(
                launch_error_timeout=float(launch_error_timeout),
                launch_retry_timeout=float(launch_retry_timeout),
                terminate_timeout=float(terminate_timeout),
                operation_duration=float(operation_duration),
            ),
            post_process_arguments=[],
        )

    async def test_instruments_with_partial_timings(self) -> None:
        self.client_mock.run_instruments = AsyncMock()
        template_name = "System Trace"
        trace_path = "trace.trace"
        launch_retry_timeout, terminate_timeout = ("200.0", "200.0")
        await cli_main(
            cmd_input=[
                "instruments",
                "--output",
                trace_path,
                "--template",
                template_name,
                "--app-args",
                "perfLab",
                "--launch-retry-timeout",
                launch_retry_timeout,
                "--terminate-timeout",
                terminate_timeout,
            ]
        )
        self.client_mock.run_instruments.assert_called_once_with(
            stop=ANY,
            trace_basename="trace",
            template_name=template_name,
            app_bundle_id=None,
            app_environment={},
            app_arguments=["perfLab"],
            tool_arguments=None,
            timings=InstrumentsTimings(
                launch_error_timeout=None,
                launch_retry_timeout=float(launch_retry_timeout),
                terminate_timeout=float(terminate_timeout),
                operation_duration=None,
            ),
            post_process_arguments=[],
        )

    async def test_add_media(self) -> None:
        self.client_mock.add_media = AsyncMock(return_value=["aaa", "bbb"])
        file_paths = ["cat.jpeg", "dog.mov"]
        await cli_main(cmd_input=["add-media"] + file_paths)
        self.client_mock.add_media.assert_called_once_with(file_paths=file_paths)

    async def test_focus(self) -> None:
        self.client_mock.focus = AsyncMock(return_value=["aaa", "bbb"])
        await cli_main(cmd_input=["focus"])
        self.client_mock.focus.assert_called_once()

    async def test_debugserver_start(self) -> None:
        self.client_mock.debugserver_start = AsyncMock(return_value=["aaa", "bbb"])
        await cli_main(cmd_input=["debugserver", "start", "com.foo.bar"])
        self.client_mock.debugserver_start.assert_called_once_with(
            bundle_id="com.foo.bar"
        )

    async def test_debugserver_stop(self) -> None:
        self.client_mock.debugserver_stop = AsyncMock(return_value=["aaa", "bbb"])
        await cli_main(cmd_input=["debugserver", "stop"])
        self.client_mock.debugserver_stop.assert_called_once()

    async def test_debugserver_status(self) -> None:
        self.client_mock.debugserver_status = AsyncMock(return_value=["aaa", "bbb"])
        await cli_main(cmd_input=["debugserver", "status"])
        self.client_mock.debugserver_status.assert_called_once()

    async def test_xctrace_record_with_package(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        package = "fb_signpost"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--package",
                package,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=package,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_launch_args(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        process_to_launch = "com.facebook.Wilde"
        launch_args = ["foo", "bar"]
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--template",
                template_name,
                "--launch",
                process_to_launch,
                *launch_args,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=False,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=process_to_launch,
            process_env={},
            launch_args=launch_args,
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_process_env(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        process_to_launch = "com.facebook.Wilde"
        process_env = {"foo": "bar", "baz": "qux"}
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--template",
                template_name,
                "--launch",
                process_to_launch,
                "--env",
                "foo=bar",
                "--env",
                "baz=qux",
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=False,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=process_to_launch,
            process_env=process_env,
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_time_limit(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        time_limit = "4m"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--time-limit",
                time_limit,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=240.0,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_stop_timeout(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        stop_timeout = "60s"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--stop-timeout",
                stop_timeout,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=60.0,
        )

    async def test_xctrace_record_with_attach(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        process_to_attach = "123"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--template",
                template_name,
                "--attach",
                process_to_attach,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=False,
            time_limit=None,
            package=None,
            process_to_attach=process_to_attach,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_target_stdin(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        target_stdin = "-"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--target-stdin",
                target_stdin,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=target_stdin,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_target_stdout(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        target_stdout = "-"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--target-stdout",
                target_stdout,
                "--output",
                trace_path,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=target_stdout,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_with_post_args(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        post_args = ["instrumental", "convert"]
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--output",
                trace_path,
                "--post-args",
                *post_args,
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=post_args,
            stop_timeout=None,
        )

    async def test_xctrace_record_with_ignored_options(self) -> None:
        self.client_mock.xctrace_record = AsyncMock()
        template_name = "Time Profiler"
        device = "9d86342f4761d4c28d99c7ed5df95d2d641fb3c4"
        trace_path = "trace.trace"
        await cli_main(
            cmd_input=[
                "xctrace",
                "record",
                "--all-processes",
                "--template",
                template_name,
                "--output",
                trace_path,
                "--device",
                device,
                "--append-run",
            ]
        )
        self.client_mock.xctrace_record.assert_called_once_with(
            stop=ANY,
            output="trace",
            template_name=template_name,
            all_processes=True,
            time_limit=None,
            package=None,
            process_to_attach=None,
            process_to_launch=None,
            process_env={},
            launch_args=[],
            target_stdin=None,
            target_stdout=None,
            post_args=[],
            stop_timeout=None,
        )

    async def test_xctrace_record_without_target(self) -> None:
        self.assertEqual(
            await cli_main(
                cmd_input=[
                    "xctrace",
                    "record",
                    "--template",
                    "Time Profiler",
                    "--output",
                    "trace.trace",
                ]
            ),
            2,  # error code when the required arguemt is not provided
        )

    async def test_xctrace_record_with_duplicated_targets(self) -> None:
        self.assertEqual(
            await cli_main(
                cmd_input=[
                    "xctrace",
                    "record",
                    "--all-processes",
                    "--launch",
                    "com.facebook.Wilde",
                    "--template",
                    "Time Profiler",
                    "--output",
                    "trace.trace",
                ]
            ),
            2,  # error code when mutually exclusive arguments are provided
        )
