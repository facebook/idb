#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
from enum import Enum
from io import StringIO
from abc import ABCMeta

from typing import List, NamedTuple, Optional, Set, Union, Dict, Tuple, AsyncIterator

LoggingMetadata = Dict[str, Optional[Union[str, List[str], int, float]]]


class Address(NamedTuple):
    host: str
    grpc_port: int
    port: Optional[int] = None


class AppProcessState(Enum):
    UNKNOWN = 0
    NOT_RUNNING = 1
    RUNNING = 2


class InstalledAppInfo(NamedTuple):
    bundle_id: str
    name: str
    architectures: Set[str]
    install_type: str
    process_state: AppProcessState
    debuggable: bool


class HIDButtonType(Enum):
    APPLE_PAY = 1
    HOME = 2
    LOCK = 3
    SIDE_BUTTON = 4
    SIRI = 5


ConnectionDestination = Union[str, Address]


class CompanionInfo(NamedTuple):
    udid: str
    host: str
    port: int
    is_local: bool
    grpc_port: int


class ScreenDimensions(NamedTuple):
    width: int
    height: int
    density: Optional[float]
    width_points: Optional[int]
    height_points: Optional[int]


class TargetDescription(NamedTuple):
    udid: str
    name: str
    state: Optional[str]
    target_type: Optional[str]
    os_version: Optional[str]
    architecture: Optional[str]
    companion_info: Optional[CompanionInfo]
    screen_dimensions: Optional[ScreenDimensions]


class DaemonInfo(NamedTuple):
    host: str
    port: int
    targets: List[TargetDescription]


ConnectResponse = Union[CompanionInfo, DaemonInfo]


class FileEntryInfo(NamedTuple):
    path: str


class IdbException(Exception):
    pass


class AccessibilityInfo(NamedTuple):
    json: Optional[str]


class CrashLogInfo(NamedTuple):
    name: Optional[str]
    bundle_id: Optional[str]
    process_name: Optional[str]
    parent_process_name: Optional[str]
    process_identifier: Optional[int]
    parent_process_identifier: Optional[int]
    timestamp: Optional[int]


class CrashLog(NamedTuple):
    info: Optional[CrashLogInfo]
    contents: Optional[str]


class CrashLogQuery(NamedTuple):
    since: Optional[int] = None
    before: Optional[int] = None
    bundle_id: Optional[str] = None
    name: Optional[str] = None


class TestRunFailureInfo(NamedTuple):
    message: str
    file: str
    line: int


class TestActivity(NamedTuple):
    title: str
    duration: float
    uuid: str


class TestRunInfo(NamedTuple):
    bundle_name: str
    class_name: str
    method_name: str
    logs: List[str]
    duration: float
    passed: bool
    failure_info: Optional[TestRunFailureInfo]
    activityLogs: Optional[List[TestActivity]]
    crashed: bool


class InstalledTestInfo(NamedTuple):
    bundle_id: str
    name: Optional[str]
    architectures: Optional[Set[str]]


class IdbClientBase:
    async def list_apps(self) -> List[InstalledAppInfo]:
        pass

    async def launch(
        self,
        bundle_id: str,
        env: Optional[Dict[str, str]] = None,
        args: Optional[List[str]] = None,
        foreground_if_running: bool = False,
        stop: Optional[asyncio.Event] = None,
    ) -> None:
        pass

    async def run_xctest(
        self,
        test_bundle_id: str,
        app_bundle_id: str,
        test_host_app_bundle_id: Optional[str] = None,
        is_ui_test: bool = False,
        is_logic_test: bool = False,
        tests_to_run: Optional[Set[str]] = None,
        tests_to_skip: Optional[Set[str]] = None,
        env: Optional[Dict[str, str]] = None,
        args: Optional[List[str]] = None,
        result_bundle_path: Optional[str] = None,
        idb_log_buffer: Optional[StringIO] = None,
        timeout: Optional[int] = None,
        poll_interval_sec: float = 0.5,
    ) -> AsyncIterator[TestRunInfo]:
        yield

    async def install(self, bundle_path: str) -> str:
        pass

    async def uninstall(self, bundle_id: str) -> None:
        pass

    async def install_dylib(self, dylib_path: str) -> str:
        pass

    async def install_xctest(self, bundle_path: str) -> str:
        pass

    async def connect(
        self,
        destination: Union[Address, str],
        metadata: Optional[Dict[str, str]] = None,
    ) -> None:
        return

    async def disconnect(self, destination: Union[Address, str]) -> None:
        pass

    async def list_targets(self) -> List[TargetDescription]:
        pass

    async def list_xctests(self) -> List[InstalledTestInfo]:
        pass

    async def terminate(self, bundle_id: str) -> None:
        pass

    async def pull(self, bundle_id: str, src_path: str, dest_path: str) -> None:
        pass

    async def mkdir(self, bundle_id: str, path: str) -> None:
        pass

    async def list_test_bundle(self, test_bundle_id: str) -> List[str]:
        pass

    async def tail_logs(
        self, stop: asyncio.Event, arguments: Optional[List[str]] = None
    ) -> AsyncIterator[str]:
        yield

    async def push(self, src_paths: List[str], bundle_id: str, dest_path: str) -> None:
        pass

    async def clear_keychain(self) -> None:
        pass

    async def boot(self) -> None:
        pass

    async def open_url(self, url: str) -> None:
        pass

    async def set_location(self, latitude: float, longitude: float) -> None:
        pass

    async def approve(self, bundle_id: str, permissions: Set[str]) -> None:
        pass

    async def record_video(self, stop: asyncio.Event, output_file: str) -> None:
        pass

    async def screenshot(self) -> bytes:
        pass

    async def tap(self, x: int, y: int, duration: Optional[float] = None) -> None:
        pass

    async def button(
        self, button_type: HIDButtonType, duration: Optional[float] = None
    ) -> None:
        pass

    async def key(self, keycode: int, duration: Optional[float] = None) -> None:
        return

    async def key_sequence(self, key_sequence: List[int]) -> None:
        pass

    async def swipe(
        self,
        p_start: Tuple[int, int],
        p_end: Tuple[int, int],
        delta: Optional[int] = None,
    ) -> None:
        pass

    async def crash_show(self, name: str) -> CrashLog:
        pass

    async def contacts_update(self, contacts_path: str) -> None:
        pass

    async def describe(self) -> TargetDescription:
        pass

    async def accessibility_info(
        self, point: Optional[Tuple[int, int]]
    ) -> AccessibilityInfo:
        pass

    async def run_instruments(
        self,
        stop: asyncio.Event,
        template: str,
        app_bundle_id: str,
        trace_path: str,
        post_process_arguments: Optional[List[str]] = None,
        env: Optional[Dict[str, str]] = None,
        app_args: Optional[List[str]] = None,
        started: Optional[asyncio.Event] = None,
    ) -> None:
        return

    async def start_instruments(
        self,
        template: str,
        app_bundle_id: str,
        env: Optional[Dict[str, str]] = None,
        app_args: Optional[List[str]] = None,
    ) -> Optional[str]:
        return

    async def stop_instruments(
        self, session_id: str, post_process_arguments: Optional[List[str]] = None
    ) -> Tuple[Optional[bytes], Optional[str]]:
        pass

    async def crash_list(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        pass

    async def crash_delete(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        pass

    async def add_metadata(self, metadata: Optional[Dict[str, str]]) -> None:
        pass

    async def add_media(self, file_paths: List[str]) -> None:
        pass

    async def focus(self) -> None:
        pass

    async def tail_logs_contextmanager(self) -> AsyncIterator[str]:
        yield

    async def debugserver_start(self, bundle_id: str) -> List[str]:
        pass

    async def debugserver_stop(self) -> None:
        pass

    async def debugserver_status(self) -> Optional[List[str]]:
        pass

    async def text(self, text: str) -> None:
        return

    async def ls(self, bundle_id: str, path: str) -> List[FileEntryInfo]:
        pass

    async def mv(self, bundle_id: str, src_paths: List[str], dest_path: str) -> None:
        pass

    async def rm(self, bundle_id: str, paths: List[str]) -> None:
        pass


class Server(metaclass=ABCMeta):
    def close(self) -> None:
        pass

    async def wait_closed(self) -> None:
        pass

    @property
    def ports(self) -> Dict[str, str]:
        pass
