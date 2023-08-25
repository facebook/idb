#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import json
from abc import ABC, abstractmethod, abstractproperty
from asyncio import StreamReader, StreamWriter
from dataclasses import asdict, dataclass, field
from datetime import timedelta
from enum import Enum
from io import StringIO
from typing import (
    AsyncContextManager,
    AsyncGenerator,
    AsyncIterable,
    AsyncIterator,
    Dict,
    IO,
    List,
    Mapping,
    Optional,
    Set,
    Tuple,
    Union,
)


LoggingMetadata = Dict[str, Optional[Union[str, List[str], int, float]]]


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


class TargetType(str, Enum):
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
    architectures: Set[str]
    install_type: str
    process_state: AppProcessState
    debuggable: bool
    process_id: int


@dataclass(frozen=True)
class InstrumentsTimings:
    launch_error_timeout: Optional[float] = None
    launch_retry_timeout: Optional[float] = None
    terminate_timeout: Optional[float] = None
    operation_duration: Optional[float] = None


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
    pid: Optional[int]
    address: Address
    metadata: LoggingMetadata = field(default_factory=dict)


@dataclass(frozen=True)
class ScreenDimensions:
    width: int
    height: int
    density: Optional[float]
    width_points: Optional[int]
    height_points: Optional[int]


DeviceDetails = Mapping[str, Union[int, str]]


@dataclass(frozen=True)
class TargetDescription:
    udid: str
    name: str
    target_type: TargetType
    state: Optional[str]
    os_version: Optional[str]
    architecture: Optional[str]
    companion_info: Optional[CompanionInfo]
    screen_dimensions: Optional[ScreenDimensions]
    model: Optional[str] = None
    device: Optional[DeviceDetails] = None
    extended: Optional[DeviceDetails] = None
    diagnostics: Optional[DeviceDetails] = None
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
    entries: List[FileEntryInfo]


@dataclass(frozen=True)
class AccessibilityInfo:
    json: str


@dataclass(frozen=True)
class CrashLogInfo:
    name: Optional[str]
    bundle_id: Optional[str]
    process_name: Optional[str]
    parent_process_name: Optional[str]
    process_identifier: Optional[int]
    parent_process_identifier: Optional[int]
    timestamp: Optional[int]


@dataclass(frozen=True)
class CrashLog:
    info: Optional[CrashLogInfo]
    contents: Optional[str]


@dataclass(frozen=True)
class CrashLogQuery:
    since: Optional[int] = None
    before: Optional[int] = None
    bundle_id: Optional[str] = None
    name: Optional[str] = None


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
    attachments: List[TestAttachment]
    sub_activities: List["TestActivity"]


@dataclass(frozen=True)
class TestRunInfo:
    bundle_name: str
    class_name: str
    method_name: str
    logs: List[str]
    duration: float
    passed: bool
    failure_info: Optional[TestRunFailureInfo]
    activityLogs: Optional[List[TestActivity]]
    crashed: bool

    @property
    def crashed_outside_test_case(self) -> bool:
        return self.crashed and self.class_name == "" and self.method_name == ""


@dataclass(frozen=True)
class InstalledTestInfo:
    bundle_id: str
    name: Optional[str]
    architectures: Optional[Set[str]]


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
    delta: Optional[float]
    duration: Optional[float]


@dataclass(frozen=True)
class HIDDelay:
    duration: float


HIDEvent = Union[HIDPress, HIDSwipe, HIDDelay]


@dataclass(frozen=True)
class InstalledArtifact:
    name: str
    uuid: Optional[str]
    progress: Optional[float]


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
        self, device_type: str, os_version: str, timeout: Optional[timedelta] = None
    ) -> TargetDescription:
        pass

    @abstractmethod
    async def boot(
        self, udid: str, verify: bool = True, timeout: Optional[timedelta] = None
    ) -> None:
        pass

    @abstractmethod
    async def boot_headless(  # pyre-fixme
        self, udid: str, verify: bool = True, timeout: Optional[timedelta] = None
    ) -> AsyncContextManager[None]:
        yield

    @abstractmethod
    async def shutdown(self, udid: str, timeout: Optional[timedelta] = None) -> None:
        pass

    @abstractmethod
    async def erase(self, udid: str, timeout: Optional[timedelta] = None) -> None:
        pass

    @abstractmethod
    async def clone(
        self,
        udid: str,
        destination_device_set: Optional[str] = None,
        timeout: Optional[timedelta] = None,
    ) -> TargetDescription:
        pass

    @abstractmethod
    async def delete(
        self, udid: Optional[str], timeout: Optional[timedelta] = None
    ) -> None:
        pass

    @abstractmethod
    async def clean(self, udid: str, timeout: Optional[timedelta] = None) -> None:
        pass

    @abstractmethod
    async def list_targets(
        self, only: Optional[OnlyFilter] = None, timeout: Optional[timedelta] = None
    ) -> List[TargetDescription]:
        pass

    @abstractmethod
    async def tail_targets(
        self, only: Optional[OnlyFilter] = None
    ) -> AsyncGenerator[List[TargetDescription], None]:
        yield

    @abstractmethod
    async def target_description(
        self,
        udid: Optional[str] = None,
        only: Optional[OnlyFilter] = None,
        timeout: Optional[timedelta] = None,
    ) -> TargetDescription:
        pass

    @abstractmethod
    async def unix_domain_server(  # pyre-fixme
        self, udid: str, path: str, only: Optional[OnlyFilter] = None
    ) -> AsyncContextManager[str]:
        yield


# Exposes the resource-specific commands that imply a connected companion
class Client(ABC):
    @abstractmethod
    async def list_apps(
        self, fetch_process_state: bool = True
    ) -> List[InstalledAppInfo]:
        pass

    @abstractmethod
    async def launch(
        self,
        bundle_id: str,
        env: Optional[Dict[str, str]] = None,
        args: Optional[List[str]] = None,
        foreground_if_running: bool = False,
        wait_for_debugger: bool = False,
        stop: Optional[asyncio.Event] = None,
        pid_file: Optional[str] = None,
    ) -> None:
        pass

    @abstractmethod
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
        report_activities: bool = False,
        report_attachments: bool = False,
        activities_output_path: Optional[str] = None,
        coverage_output_path: Optional[str] = None,
        enable_continuous_coverage_collection: bool = False,
        coverage_format: CodeCoverageFormat = CodeCoverageFormat.EXPORTED,
        log_directory_path: Optional[str] = None,
        wait_for_debugger: bool = False,
    ) -> AsyncIterator[TestRunInfo]:
        yield

    @abstractmethod
    async def install(
        self,
        bundle: Union[str, IO[bytes]],
        compression: Optional[Compression] = None,
        make_debuggable: Optional[bool] = None,
        override_modification_time: Optional[bool] = None,
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_dylib(
        self, dylib: Union[str, IO[bytes]]
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_dsym(
        self,
        dsym: Union[str, IO[bytes]],
        bundle_id: Optional[str],
        compression: Optional[Compression],
        bundle_type: Optional[FileContainerType] = None,
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_xctest(
        self, xctest: Union[str, IO[bytes]], skip_signing_bundles: Optional[bool] = None
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def install_framework(
        self, framework_path: Union[str, IO[bytes]]
    ) -> AsyncIterator[InstalledArtifact]:
        yield

    @abstractmethod
    async def uninstall(self, bundle_id: str) -> None:
        pass

    @abstractmethod
    async def list_xctests(self) -> List[InstalledTestInfo]:
        pass

    @abstractmethod
    async def terminate(self, bundle_id: str) -> None:
        pass

    @abstractmethod
    async def list_test_bundle(self, test_bundle_id: str, app_path: str) -> List[str]:
        pass

    @abstractmethod
    async def tail_logs(
        self, stop: asyncio.Event, arguments: Optional[List[str]] = None
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
        self, name: str, value: str, value_type: str, domain: Optional[str]
    ) -> None:
        pass

    @abstractmethod
    async def get_locale(self) -> str:
        pass

    @abstractmethod
    async def get_preference(self, name: str, domain: Optional[str]) -> str:
        pass

    @abstractmethod
    async def list_locale_identifiers(self) -> List[str]:
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
        self, bundle_id: str, permissions: Set[Permission], scheme: Optional[str] = None
    ) -> None:
        pass

    @abstractmethod
    async def revoke(
        self, bundle_id: str, permissions: Set[Permission], scheme: Optional[str] = None
    ) -> None:
        pass

    @abstractmethod
    async def record_video(self, stop: asyncio.Event, output_file: str) -> None:
        pass

    @abstractmethod
    async def stream_video(
        self,
        output_file: Optional[str],
        fps: Optional[int],
        format: VideoFormat,
        compression_quality: float,
        scale_factor: float = 1,
    ) -> AsyncGenerator[bytes, None]:
        yield

    @abstractmethod
    async def screenshot(self) -> bytes:
        pass

    @abstractmethod
    async def tap(self, x: float, y: float, duration: Optional[float] = None) -> None:
        pass

    @abstractmethod
    async def button(
        self, button_type: HIDButtonType, duration: Optional[float] = None
    ) -> None:
        pass

    @abstractmethod
    async def key(self, keycode: int, duration: Optional[float] = None) -> None:
        return

    @abstractmethod
    async def key_sequence(self, key_sequence: List[int]) -> None:
        pass

    @abstractmethod
    async def swipe(
        self,
        p_start: Tuple[int, int],
        p_end: Tuple[int, int],
        duration: Optional[float] = None,
        delta: Optional[int] = None,
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
        self, point: Optional[Tuple[int, int]], nested: bool
    ) -> AccessibilityInfo:
        pass

    @abstractmethod
    async def run_instruments(
        self,
        stop: asyncio.Event,
        trace_basename: str,
        template_name: str,
        app_bundle_id: str,
        app_environment: Optional[Dict[str, str]] = None,
        app_arguments: Optional[List[str]] = None,
        tool_arguments: Optional[List[str]] = None,
        started: Optional[asyncio.Event] = None,
        timings: Optional[InstrumentsTimings] = None,
        post_process_arguments: Optional[List[str]] = None,
    ) -> List[str]:
        pass

    @abstractmethod
    async def xctrace_record(
        self,
        stop: asyncio.Event,
        output: str,
        template_name: str,
        all_processes: bool = False,
        time_limit: Optional[float] = None,
        package: Optional[str] = None,
        process_to_attach: Optional[str] = None,
        process_to_launch: Optional[str] = None,
        process_env: Optional[Dict[str, str]] = None,
        launch_args: Optional[List[str]] = None,
        target_stdin: Optional[str] = None,
        target_stdout: Optional[str] = None,
        post_args: Optional[List[str]] = None,
        stop_timeout: Optional[float] = None,
        started: Optional[asyncio.Event] = None,
    ) -> List[str]:
        pass

    @abstractmethod
    async def crash_list(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        pass

    @abstractmethod
    async def crash_delete(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        pass

    @abstractmethod
    async def add_media(self, file_paths: List[str]) -> None:
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
        compression: Optional[Compression],
    ) -> None:
        raise NotImplementedError("Dap command not implemented")

    @abstractmethod
    async def debugserver_start(self, bundle_id: str) -> List[str]:
        pass

    @abstractmethod
    async def debugserver_stop(self) -> None:
        pass

    @abstractmethod
    async def debugserver_status(self) -> Optional[List[str]]:
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
    ) -> List[FileEntryInfo]:
        pass

    @abstractmethod
    async def ls(self, container: FileContainer, paths: List[str]) -> List[FileListing]:
        pass

    @abstractmethod
    async def mv(
        self, container: FileContainer, src_paths: List[str], dest_path: str
    ) -> None:
        pass

    @abstractmethod
    async def rm(self, container: FileContainer, paths: List[str]) -> None:
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
        src_paths: List[str],
        container: FileContainer,
        dest_path: str,
        compression: Optional[Compression],
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
        metadata: Optional[Dict[str, str]] = None,
    ) -> CompanionInfo:
        pass

    @abstractmethod
    async def disconnect(self, destination: Union[Address, str]) -> None:
        pass

    @abstractmethod
    async def list_targets(
        self, only: Optional[OnlyFilter] = None
    ) -> List[TargetDescription]:
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
    def ports(self) -> Dict[str, str]:
        pass
