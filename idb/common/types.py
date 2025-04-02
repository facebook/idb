#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import asyncio
import json
from abc import ABC, abstractmethod, abstractproperty
from asyncio import StreamReader, StreamWriter
from collections.abc import AsyncGenerator, AsyncIterable, AsyncIterator, Mapping
from contextlib import asynccontextmanager
from dataclasses import asdict, dataclass, field
from datetime import timedelta
from enum import Enum
from io import StringIO
from typing import Dict, IO, List, Optional, Set, Tuple, Union

from python.migrations.py310 import StrEnum310


LoggingMetadata = dict[str, Optional[Union[str, list[str], int, float]]]


class IdbException(Exception):
    pass


class IdbConnectionException(Exception):
    pass


class Permission(Enum):
    PHOTOS = 0
    CAMERA = 1
    CONTACTS = 2
    URL = 3
    LOCATION = 4
    NOTIFICATION = 5
    MICROPHONE = 6


class TargetType(StrEnum310):
    DEVICE = "device"
    SIMULATOR = "simulator"
    MAC = "mac"


@dataclass(frozen=True)
class ECIDFilter:
    ecid: int


OnlyFilter = Union[TargetType, ECIDFilter]


class Architecture(Enum):
    ANY = "any"
    X86 = "x86_64"
    ARM64 = "arm64"


class VideoFormat(Enum):
    H264 = "h264"
    RBGA = "rbga"
    MJPEG = "mjpeg"
    MINICAP = "minicap"


@dataclass(frozen=True)
class TCPAddress:
    host: str
    port: int


@dataclass(frozen=True)
class DomainSocketAddress:
    path: str


Address = Union[TCPAddress, DomainSocketAddress]


class AppProcessState(Enum):
    UNKNOWN = 0
    NOT_RUNNING = 1
    RUNNING = 2


@dataclass(frozen=True)
class InstalledAppInfo:
    bundle_id: str
    name: str
    architectures: set[str]
    install_type: str
    process_state: AppProcessState
    debuggable: bool
    process_id: int


@dataclass(frozen=True)
class InstrumentsTimings:
    launch_error_timeout: float | None = None
    launch_retry_timeout: float | None = None
    terminate_timeout: float | None = None
    operation_duration: float | None = None


class HIDButtonType(Enum):
    APPLE_PAY = 1
    HOME = 2
    LOCK = 3
    SIDE_BUTTON = 4
    SIRI = 5


ConnectionDestination = Union[str, Address]


@dataclass(frozen=True)
class CompanionInfo:
    udid: str
    is_local: bool
    pid: int | None
    address: Address
    metadata: LoggingMetadata = field(default_factory=dict)


@dataclass(frozen=True)
class ScreenDimensions:
    width: int
    height: int
    density: float | None
    width_points: int | None
    height_points: int | None


DeviceDetails = Mapping[str, Union[int, str]]


@dataclass(frozen=True)
class TargetDescription:
    udid: str
    name: str
    target_type: TargetType
    state: str | None
    os_version: str | None
    architecture: str | None
    companion_info: CompanionInfo | None
    screen_dimensions: ScreenDimensions | None
    model: str | None = None
    device: DeviceDetails | None = None
    extended: DeviceDetails | None = None
    diagnostics: DeviceDetails | None = None
    metadata: LoggingMetadata = field(default_factory=dict)

    @property
    def as_json(self) -> str:
        return json.dumps(asdict(self))


@dataclass(frozen=True)
class FileEntryInfo:
    path: str


@dataclass(frozen=True)
class FileListing:
    parent: str
    entries: list[FileEntryInfo]


@dataclass(frozen=True)
class AccessibilityInfo:
    json: str


@dataclass(frozen=True)
class CrashLogInfo:
    name: str | None
    bundle_id: str | None
    process_name: str | None
    parent_process_name: str | None
    process_identifier: int | None
    parent_process_identifier: int | None
    timestamp: int | None


@dataclass(frozen=True)
class CrashLog:
    info: CrashLogInfo | None
    contents: str | None


@dataclass(frozen=True)
class CrashLogQuery:
    since: int | None = None
    before: int | None = None
    bundle_id: str | None = None
    name: str | None = None


@dataclass(frozen=True)
class TestRunFailureInfo:
    message: str
    file: str
    line: int


@dataclass(frozen=True)
class TestAttachment:
    payload: bytes
    timestamp: float
    name: str
    uniform_type_identifier: str
    user_info_json: bytes


@dataclass(frozen=True)
class TestActivity:
    title: str
    duration: float
    uuid: str
    activity_type: str
    start: float
    finish: float
    name: str
    attachments: list[TestAttachment]
    sub_activities: list["TestActivity"]


@dataclass(frozen=True)
class TestRunInfo:
    bundle_name: str
    class_name: str
    method_name: str
    logs: list[str]
    duration: float
    passed: bool
    failure_info: TestRunFailureInfo | None
    activityLogs: list[TestActivity] | None
    crashed: bool

    @property
    def crashed_outside_test_case(self) -> bool:
        return self.crashed and self.class_name == "" and self.method_name == ""


@dataclass(frozen=True)
class InstalledTestInfo:
    bundle_id: str
    name: str | None
    architectures: set[str] | None


@dataclass(frozen=True)
class DebuggerInfo:
    pid: int


class HIDDirection(Enum):
    DOWN = 0
    UP = 1


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class HIDTouch:
    point: Point


@dataclass(frozen=True)
class HIDButton:
    button: HIDButtonType


@dataclass(frozen=True)
class HIDKey:
    keycode: int


HIDPressAction = Union[HIDTouch, HIDButton, HIDKey]


@dataclass(frozen=True)
class HIDPress:
    action: HIDPressAction
    direction: HIDDirection


@dataclass(frozen=True)
class HIDSwipe:
    start: Point
    end: Point
    delta: float | None
    duration: float | None


@dataclass(frozen=True)
class HIDDelay:
    duration: float


HIDEvent = Union[HIDPress, HIDSwipe, HIDDelay]


@dataclass(frozen=True)
class InstalledArtifact:
    name: str
    uuid: str | None
    progress: float | None


class FileContainerType(Enum):
    APPLICATION = "application"
    AUXILLARY = "auxillary"
    CRASHES = "crashes"
    DISK_IMAGES = "disk_images"
    DSYM = "dsym"
    DYLIB = "dylib"
    FRAMEWORK = "framework"
    GROUP = "group"
    MDM_PROFILES = "mdm_profiles"
    MEDIA = "media"
    PROVISIONING_PROFILES = "provisioning_profiles"
    ROOT = "root"
    SPRINGBOARD_ICONS = "springboard_icons"
    SYMBOLS = "symbols"
    WALLPAPER = "wallpaper"
    XCTEST = "xctest"


FileContainer = Optional[Union[str, FileContainerType]]


class Compression(Enum):
    GZIP = 0
    ZSTD = 1


class CodeCoverageFormat(Enum):
    EXPORTED = 0
    RAW = 1


class Companion(ABC):
    @abstractmethod
    async def create(
        self, device_type: str, os_version: str, timeout: timedelta | None = None
    ) -> TargetDescription:
        pass

    @abstractmethod
    async def boot(
        self, udid: str, verify: bool = True, timeout: timedelta | None = None
    ) -> None:
        pass

    @abstractmethod
    @asynccontextmanager
    async def boot_headless(
        self, udid: str, verify: bool = True, timeout: timedelta | None = None
    ) -> AsyncGenerator[None, None]:
        yield

    @abstractmethod
    async def shutdown(self, udid: str, timeout: timedelta | None = None) -> None:
        pass

    @abstractmethod
    async def erase(self, udid: str, timeout: timedelta | None = None) -> None:
        pass

    @abstractmethod
    async def clone(
        self,
        udid: str,
        destination_device_set: str | None = None,
        timeout: timedelta | None = None,
    ) -> TargetDescription:
        pass

    @abstractmethod
    async def delete(self, udid: str | None, timeout: timedelta | None = None) -> None:
        pass

    @abstractmethod
    async def clean(self, udid: str, timeout: timedelta | None = None) -> None:
        pass

    @abstractmethod
    async def list_targets(
        self, only: OnlyFilter | None = None, timeout: timedelta | None = None
    ) -> list[TargetDescription]:
        pass

    @abstractmethod
    async def tail_targets(
        self, only: OnlyFilter | None = None
    ) -> AsyncGenerator[list[TargetDescription], None]:
        yield

    @abstractmethod
    async def target_description(
        self,
        udid: str | None = None,
        only: OnlyFilter | None = None,
        timeout: timedelta | None = None,
    ) -> TargetDescription:
        pass

    @abstractmethod
    @asynccontextmanager
    async def unix_domain_server(
        self, udid: str, path: str, only: OnlyFilter | None = None
    ) -> AsyncGenerator[str, None]:
        yield


# Exposes the resource-specific commands that imply a connected companion
class Client(ABC):
    @abstractmethod
    async def list_apps(
        self, fetch_process_state: bool = True
    ) -> list[InstalledAppInfo]:
        pass

    @abstractmethod
    async def launch(
        self,
        bundle_id: str,
        env: dict[str, str] | None = None,
        args: list[str] | None = None,
        foreground_if_running: bool = False,
        wait_for_debugger: bool = False,
        stop: asyncio.Event | None = None,
        pid_file: str | None = None,
    ) -> None:
        pass

    @abstractmethod
    async def run_xctest(
        self,
        test_bundle_id: str,
        app_bundle_id: str,
        test_host_app_bundle_id: str | None = None,
        is_ui_test: bool = False,
        is_logic_test: bool = False,
        tests_to_run: set[str] | None = None,
        tests_to_skip: set[str] | None = None,
        env: dict[str, str] | None = None,
        args: list[str] | None = None,
        result_bundle_path: str | None = None,
        idb_log_buffer: StringIO | None = None,
        timeout: int | None = None,
        poll_interval_sec: float = 0.5,
        report_activities: bool = False,
        report_attachments: bool = False,
        activities_output_path: str | None = None,
        coverage_output_path: str | None = None,
        enable_continuous_coverage_collection: bool = False,
        coverage_format: CodeCoverageFormat = CodeCoverageFormat.EXPORTED,
        log_directory_path: str | None = None,
        wait_for_debugger: bool = False,
    ) -> AsyncIterator[TestRunInfo]:
        yield

    @abstractmethod
    async def install(
        self,
        bundle: str | IO[bytes],
        compression: Compression | None = None,
        make_debuggable: bool | None = None,
        override_modification_time: bool | None = None,
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_dylib(
        self, dylib: str | IO[bytes]
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_dsym(
        self,
        dsym: str | IO[bytes],
        bundle_id: str | None,
        compression: Compression | None,
        bundle_type: FileContainerType | None = None,
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_xctest(
        self, xctest: str | IO[bytes], skip_signing_bundles: bool | None = None
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_framework(
        self, framework_path: str | IO[bytes]
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def uninstall(self, bundle_id: str) -> None:
        pass

    @abstractmethod
    async def list_xctests(self) -> list[InstalledTestInfo]:
        pass

    @abstractmethod
    async def terminate(self, bundle_id: str) -> None:
        pass

    @abstractmethod
    async def list_test_bundle(self, test_bundle_id: str, app_path: str) -> list[str]:
        pass

    @abstractmethod
    async def tail_logs(
        self, stop: asyncio.Event, arguments: list[str] | None = None
    ) -> AsyncIterator[str]:
        yield

    @abstractmethod
    async def tail_companion_logs(self, stop: asyncio.Event) -> AsyncIterator[str]:
        yield

    @abstractmethod
    async def clear_keychain(self) -> None:
        pass

    @abstractmethod
    async def set_hardware_keyboard(self, enabled: bool) -> None:
        pass

    @abstractmethod
    async def set_locale(self, locale_identifier: str) -> None:
        pass

    @abstractmethod
    async def set_preference(
        self, name: str, value: str, value_type: str, domain: str | None
    ) -> None:
        pass

    @abstractmethod
    async def get_locale(self) -> str:
        pass

    @abstractmethod
    async def get_preference(self, name: str, domain: str | None) -> str:
        pass

    @abstractmethod
    async def list_locale_identifiers(self) -> list[str]:
        pass

    @abstractmethod
    async def open_url(self, url: str) -> None:
        pass

    @abstractmethod
    async def set_location(self, latitude: float, longitude: float) -> None:
        pass

    @abstractmethod
    async def simulate_memory_warning(self) -> None:
        pass

    @abstractmethod
    async def send_notification(self, bundle_id: str, json_payload: str) -> None:
        pass

    @abstractmethod
    async def approve(
        self, bundle_id: str, permissions: set[Permission], scheme: str | None = None
    ) -> None:
        pass

    @abstractmethod
    async def revoke(
        self, bundle_id: str, permissions: set[Permission], scheme: str | None = None
    ) -> None:
        pass

    @abstractmethod
    async def record_video(self, stop: asyncio.Event, output_file: str) -> None:
        pass

    @abstractmethod
    async def stream_video(
        self,
        output_file: str | None,
        fps: int | None,
        format: VideoFormat,
        compression_quality: float,
        scale_factor: float = 1,
    ) -> AsyncGenerator[bytes, None]:
        yield

    @abstractmethod
    async def screenshot(self) -> bytes:
        pass

    @abstractmethod
    async def tap(self, x: float, y: float, duration: float | None = None) -> None:
        pass

    @abstractmethod
    async def button(
        self, button_type: HIDButtonType, duration: float | None = None
    ) -> None:
        pass

    @abstractmethod
    async def key(self, keycode: int, duration: float | None = None) -> None:
        return

    @abstractmethod
    async def key_sequence(self, key_sequence: list[int]) -> None:
        pass

    @abstractmethod
    async def swipe(
        self,
        p_start: tuple[int, int],
        p_end: tuple[int, int],
        duration: float | None = None,
        delta: int | None = None,
    ) -> None:
        pass

    @abstractmethod
    async def crash_show(self, name: str) -> CrashLog:
        pass

    @abstractmethod
    async def contacts_update(self, contacts_path: str) -> None:
        pass

    @abstractmethod
    async def describe(self, fetch_diagnostics: bool = False) -> TargetDescription:
        pass

    @abstractmethod
    async def accessibility_info(
        self, point: tuple[int, int] | None, nested: bool
    ) -> AccessibilityInfo:
        pass

    @abstractmethod
    async def run_instruments(
        self,
        stop: asyncio.Event,
        trace_basename: str,
        template_name: str,
        app_bundle_id: str,
        app_environment: dict[str, str] | None = None,
        app_arguments: list[str] | None = None,
        tool_arguments: list[str] | None = None,
        started: asyncio.Event | None = None,
        timings: InstrumentsTimings | None = None,
        post_process_arguments: list[str] | None = None,
    ) -> list[str]:
        pass

    @abstractmethod
    async def xctrace_record(
        self,
        stop: asyncio.Event,
        output: str,
        template_name: str,
        all_processes: bool = False,
        time_limit: float | None = None,
        package: str | None = None,
        process_to_attach: str | None = None,
        process_to_launch: str | None = None,
        process_env: dict[str, str] | None = None,
        launch_args: list[str] | None = None,
        target_stdin: str | None = None,
        target_stdout: str | None = None,
        post_args: list[str] | None = None,
        stop_timeout: float | None = None,
        started: asyncio.Event | None = None,
    ) -> list[str]:
        pass

    @abstractmethod
    async def crash_list(self, query: CrashLogQuery) -> list[CrashLogInfo]:
        pass

    @abstractmethod
    async def crash_delete(self, query: CrashLogQuery) -> list[CrashLogInfo]:
        pass

    @abstractmethod
    async def add_media(self, file_paths: list[str]) -> None:
        pass

    @abstractmethod
    async def focus(self) -> None:
        pass

    async def dap(
        self,
        dap_path: str,
        input_stream: StreamReader,
        output_stream: StreamWriter,
        stop: asyncio.Event,
        compression: Compression | None,
    ) -> None:
        raise NotImplementedError("Dap command not implemented")

    @abstractmethod
    async def debugserver_start(self, bundle_id: str) -> list[str]:
        pass

    @abstractmethod
    async def debugserver_stop(self) -> None:
        pass

    @abstractmethod
    async def debugserver_status(self) -> list[str] | None:
        pass

    @abstractmethod
    async def text(self, text: str) -> None:
        return

    @abstractmethod
    async def hid(self, event_iterator: AsyncIterable[HIDEvent]) -> None:
        pass

    @abstractmethod
    async def ls_single(
        self, container: FileContainer, path: str
    ) -> list[FileEntryInfo]:
        pass

    @abstractmethod
    async def ls(self, container: FileContainer, paths: list[str]) -> list[FileListing]:
        pass

    @abstractmethod
    async def mv(
        self, container: FileContainer, src_paths: list[str], dest_path: str
    ) -> None:
        pass

    @abstractmethod
    async def rm(self, container: FileContainer, paths: list[str]) -> None:
        pass

    @abstractmethod
    async def mkdir(self, container: FileContainer, path: str) -> None:
        pass

    @abstractmethod
    async def pull(
        self, container: FileContainer, src_path: str, dest_path: str
    ) -> None:
        pass

    @abstractmethod
    async def push(
        self,
        src_paths: list[str],
        container: FileContainer,
        dest_path: str,
        compression: Compression | None,
    ) -> None:
        pass

    @abstractmethod
    async def tail(
        self, stop: asyncio.Event, container: FileContainer, path: str
    ) -> AsyncIterator[bytes]:
        yield


class ClientManager:
    @abstractmethod
    async def connect(
        self,
        destination: ConnectionDestination,
        metadata: dict[str, str] | None = None,
    ) -> CompanionInfo:
        pass

    @abstractmethod
    async def disconnect(self, destination: Address | str) -> None:
        pass

    @abstractmethod
    async def list_targets(
        self, only: OnlyFilter | None = None
    ) -> list[TargetDescription]:
        pass

    @abstractmethod
    async def kill(self) -> None:
        pass


class Server(ABC):
    @abstractmethod
    def close(self) -> None:
        pass

    @abstractmethod
    async def wait_closed(self) -> None:
        pass

    @abstractproperty
    def ports(self) -> dict[str, str]:
        pass
