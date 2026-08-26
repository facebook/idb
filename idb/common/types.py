#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import json
from abc import ABC, abstractmethod
from asyncio import StreamReader, StreamWriter
from collections.abc import AsyncGenerator, AsyncIterable, AsyncIterator, Mapping
from contextlib import asynccontextmanager
from dataclasses import asdict, dataclass, field
from datetime import timedelta
from enum import Enum
from io import StringIO
from typing import IO, List, Optional, Set, Tuple, Union


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


class TargetType(str, Enum):
    DEVICE = "device"
    SIMULATOR = "simulator"
    MAC = "mac"

    # enum.StrEnum is python 3.11+, and the client is installed onto older
    # interpreters. These are the two assignments StrEnum makes over a str
    # mixin: stringify and format as the value, not as "TargetType.DEVICE".
    __str__ = str.__str__
    __format__ = str.__format__


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


# The encoding of a screenshot. Values are the names the companion reports back
# in the response, so they are the wire contract as well as the CLI's choices.
class ScreenshotFormat(Enum):
    PNG = "png"
    JPEG = "jpeg"
    TIFF = "tiff"


# The unit a crop rect and a fit bound are expressed in. POINTS is the space
# tap, swipe and describe already use; it is resolved to pixels on the
# companion, which is the only side that knows the screen scale.
class ScreenshotUnit(Enum):
    PIXELS = "pixels"
    POINTS = "points"


# Top-left origin, matching the tap/swipe coordinate space. A rect that
# partially overhangs the screen is clamped by the companion, which reports the
# dimensions it actually captured.
@dataclass(frozen=True)
class ScreenshotCrop:
    x: float
    y: float
    width: float
    height: float


# Shapes the screenshot request. The defaults are the behaviour every caller got
# before the request had fields: a full-screen, unscaled PNG.
#
# Only what the wire cannot express is rejected here. A scale factor in (0, 1]
# and a crop that lies on the screen are the companion's to enforce, since a
# crop can only be judged against the screen that was actually captured, and a
# second copy of those rules would drift from the first. See __post_init__ for
# the three that the wire cannot carry as sent.
@dataclass(frozen=True)
class ScreenshotOptions:
    format: ScreenshotFormat = ScreenshotFormat.PNG
    # Lossy formats only, in (0, 1]; None means the companion's default. The
    # companion rejects one set on PNG or TIFF rather than ignoring it, so a
    # caller who believes they are getting a smaller image finds out that they
    # are not.
    compression_quality: float | None = None
    crop: ScreenshotCrop | None = None
    # A scale factor and a fit bound are alternatives on the wire, so asking for
    # both cannot be sent. One factor is applied to both axes and the image is
    # never upscaled, so the aspect ratio is preserved to within the rounding of
    # each side to a whole pixel; an unset bound is unbounded on that axis.
    scale_factor: float | None = None
    max_width: int | None = None
    max_height: int | None = None
    unit: ScreenshotUnit = ScreenshotUnit.PIXELS

    # Only the rules the wire cannot carry are checked here; everything the
    # companion can see for itself is left to it, so there is one copy of each
    # rule rather than two that drift. A scale factor of 2 or a crop with a
    # negative width travel intact and come back as INVALID_ARGUMENT. These
    # three do not travel intact:
    #
    # - a factor and a bounding box are alternatives in a proto `oneof`, so
    #   setting both silently drops one instead of being an error
    # - 0 is a proto scalar's "unset", so a compression quality of 0 arrives
    #   indistinguishable from asking for the default, and would come back a
    #   JPEG at 0.8 reported as a success
    # - the fit bounds are `uint32`, so a negative one raises out of protobuf
    #   before any of this runs, and surfaces as a traceback
    def __post_init__(self) -> None:
        if self.scale_factor is not None and (
            self.max_width is not None or self.max_height is not None
        ):
            raise ValueError(
                "A screenshot can be scaled by a factor or fitted to a bounding "
                "box, not both"
            )
        if self.compression_quality is not None and not (
            0 < self.compression_quality <= 1
        ):
            raise ValueError(
                f"Compression quality {self.compression_quality} is not in the "
                "range (0, 1]"
            )
        for name, bound in (
            ("max_width", self.max_width),
            ("max_height", self.max_height),
        ):
            if bound is not None and bound < 1:
                raise ValueError(
                    f"{name} {bound} is not a positive number of "
                    f"{self.unit.value}; leave it unset to bound only the other "
                    "axis"
                )


# Asking for nothing in particular. Named so that it can be a default argument
# without constructing one per call site, and so that "the caller configured
# something" is a single comparison.
DEFAULT_SCREENSHOT_OPTIONS: ScreenshotOptions = ScreenshotOptions()


# The bytes of a screenshot, and what the companion says they are.
#
# This is a bytes subclass rather than a wrapper because screenshot() returned
# bare bytes before it could be configured, and its callers write them to files,
# base64 them and isinstance-check them. The measurements ride along for the
# callers that want them without breaking any of that.
#
# Every measurement is None when the companion did not report one, which is the
# case for a companion older than the fields on the request.
class Screenshot(bytes):
    format: ScreenshotFormat
    width: int | None
    height: int | None
    source_width: int | None
    source_height: int | None
    # Pixels per point, so a caller can convert between the two units itself.
    # None on a target that does not report one, which is also the target that
    # refuses a request expressed in points.
    screen_scale: float | None

    def __new__(
        cls,
        data: bytes,
        format: ScreenshotFormat = ScreenshotFormat.PNG,
        width: int | None = None,
        height: int | None = None,
        source_width: int | None = None,
        source_height: int | None = None,
        screen_scale: float | None = None,
    ) -> "Screenshot":
        screenshot = super().__new__(cls, data)
        screenshot.format = format
        screenshot.width = width
        screenshot.height = height
        screenshot.source_width = source_width
        screenshot.source_height = source_height
        screenshot.screen_scale = screen_scale
        return screenshot

    def __repr__(self) -> str:
        # bytes' own repr would print the whole image into a traceback.
        def size(width: int | None, height: int | None) -> str:
            # "NonexNone" reads as a measurement rather than the absence of one.
            return (
                "unreported" if width is None or height is None else f"{width}x{height}"
            )

        return (
            f"Screenshot({len(self)} bytes, format={self.format.value}, "
            f"size={size(self.width, self.height)}, "
            f"source_size={size(self.source_width, self.source_height)}, "
            f"screen_scale={self.screen_scale})"
        )


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


class AccessibilitySearchableKey(Enum):
    LABEL = 0
    UNIQUE_ID = 1
    VALUE = 2
    TITLE = 3
    ROLE = 4
    ROLE_DESCRIPTION = 5
    SUBROLE = 6
    HELP = 7
    PLACEHOLDER = 8


@dataclass(frozen=True)
class AccessibilityPoint:
    x: int
    y: int


@dataclass(frozen=True)
class AccessibilityMarker:
    value: str
    match_key: AccessibilitySearchableKey = AccessibilitySearchableKey.LABEL
    depth: int = 10


# Selects an accessibility element to act on: a point or a marker (or None = the
# whole screen / frontmost app). This union grows as accessibility commands land.
AccessibilityTarget = Union[AccessibilityPoint, AccessibilityMarker]


# CLI names (matching the sime2e vocabulary) for the accessibility searchable
# keys, so the same marker/expected-value flags work across both CLIs.
ACCESSIBILITY_KEY_BY_NAME: dict[str, AccessibilitySearchableKey] = {
    "AXLabel": AccessibilitySearchableKey.LABEL,
    "AXUniqueId": AccessibilitySearchableKey.UNIQUE_ID,
    "AXValue": AccessibilitySearchableKey.VALUE,
    "title": AccessibilitySearchableKey.TITLE,
    "role": AccessibilitySearchableKey.ROLE,
    "role_description": AccessibilitySearchableKey.ROLE_DESCRIPTION,
    "subrole": AccessibilitySearchableKey.SUBROLE,
    "help": AccessibilitySearchableKey.HELP,
    "placeholder": AccessibilitySearchableKey.PLACEHOLDER,
}


# Which backend serves an accessibility read. Values match the wire protocol;
# None on the options means "unspecified" — the companion's historical default
# backend, and the only value an older companion understands.
class AccessibilityBackend(Enum):
    AX = 1
    AXBRIDGE = 2
    AXBRIDGE_PERSISTENT = 3


ACCESSIBILITY_BACKEND_BY_NAME: dict[str, AccessibilityBackend] = {
    "ax": AccessibilityBackend.AX,
    "axbridge": AccessibilityBackend.AXBRIDGE,
    "axbridge-persistent": AccessibilityBackend.AXBRIDGE_PERSISTENT,
}


# The output format of an accessibility read. Values match the wire protocol;
# None on the options defers to the deprecated `nested` flag, preserving the
# historical request shape.
class AccessibilityOutputFormat(Enum):
    LEGACY = 0
    NESTED = 1
    COMPLETE = 2


ACCESSIBILITY_FORMAT_BY_NAME: dict[str, AccessibilityOutputFormat] = {
    "default": AccessibilityOutputFormat.LEGACY,
    "nested": AccessibilityOutputFormat.NESTED,
    "complete": AccessibilityOutputFormat.COMPLETE,
}


# Shapes the accessibility_info request: the format, which accessibility
# keys are reported, and which backend serves the read. This grows as
# describe-all gains enrichers.
@dataclass(frozen=True)
class AccessibilityInfoOptions:
    nested: bool = False
    keys: list[str] | None = None
    backend: AccessibilityBackend | None = None
    format: AccessibilityOutputFormat | None = None
    profile: bool = False
    collect_frame_coverage: bool = False


class AccessibilityScrollDirection(Enum):
    UP = 0
    DOWN = 1
    LEFT = 2
    RIGHT = 3
    VISIBLE = 4


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


@dataclass(frozen=True)
class HIDPinch:
    center: Point
    scale: float
    duration: float
    radius: float


class HIDOrientationType(Enum):
    PORTRAIT = 0
    PORTRAIT_UPSIDE_DOWN = 1
    LANDSCAPE_LEFT = 2
    LANDSCAPE_RIGHT = 3


@dataclass(frozen=True)
class HIDOrientation:
    orientation: HIDOrientationType


@dataclass(frozen=True)
class HIDShake:
    pass


HIDEvent = Union[HIDPress, HIDSwipe, HIDDelay, HIDPinch, HIDOrientation, HIDShake]


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
        # pyrefly: ignore [invalid-yield]
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
        # pyrefly: ignore [invalid-yield]
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
        enable_repl: bool = False,
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
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def install(
        self,
        bundle: str | IO[bytes],
        compression: Compression | None = None,
        make_debuggable: bool | None = None,
        override_modification_time: bool | None = None,
    ) -> AsyncIterator[InstalledArtifact]:
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def install_dylib(
        self, dylib: str | IO[bytes]
    ) -> AsyncIterator[InstalledArtifact]:
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def install_dsym(
        self,
        dsym: str | IO[bytes],
        bundle_id: str | None,
        compression: Compression | None,
        bundle_type: FileContainerType | None = None,
    ) -> AsyncIterator[InstalledArtifact]:
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def install_xctest(
        self, xctest: str | IO[bytes], skip_signing_bundles: bool | None = None
    ) -> AsyncIterator[InstalledArtifact]:
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def install_framework(
        self, framework_path: str | IO[bytes]
    ) -> AsyncIterator[InstalledArtifact]:
        # pyrefly: ignore [invalid-yield]
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
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def tail_companion_logs(self, stop: asyncio.Event) -> AsyncIterator[str]:
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def clear_keychain(self) -> None:
        pass

    @abstractmethod
    async def set_preference(
        self, name: str, value: str, value_type: str, domain: str | None
    ) -> None:
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
        # pyrefly: ignore [invalid-yield]
        yield

    @abstractmethod
    async def screenshot(
        self, options: ScreenshotOptions = DEFAULT_SCREENSHOT_OPTIONS
    ) -> Screenshot:
        pass

    @abstractmethod
    async def tap(self, x: float, y: float, duration: float | None = None) -> None:
        pass

    @abstractmethod
    async def multi_tap(
        self,
        x: float,
        y: float,
        count: int = 2,
        duration: float | None = None,
        pause: float = 0.1,
    ) -> None:
        pass

    @abstractmethod
    async def button(
        self, button_type: HIDButtonType, duration: float | None = None
    ) -> None:
        pass

    @abstractmethod
    async def rotate(self, orientation: HIDOrientationType) -> None:
        pass

    @abstractmethod
    async def shake(self) -> None:
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
    async def contacts_clear(self) -> None:
        pass

    @abstractmethod
    async def photos_clear(self) -> None:
        pass

    @abstractmethod
    async def describe(self, fetch_diagnostics: bool = False) -> TargetDescription:
        pass

    @abstractmethod
    async def accessibility_info(
        self,
        target: AccessibilityTarget | None,
        options: AccessibilityInfoOptions,
    ) -> AccessibilityInfo:
        pass

    @abstractmethod
    async def accessibility_tap(
        self,
        target: AccessibilityTarget,
        expected_value: str | None = None,
        expected_key: AccessibilitySearchableKey = AccessibilitySearchableKey.LABEL,
    ) -> None:
        pass

    @abstractmethod
    async def accessibility_scroll(
        self,
        target: AccessibilityTarget | None,
        direction: AccessibilityScrollDirection,
    ) -> None:
        pass

    @abstractmethod
    async def accessibility_set_value(
        self,
        target: AccessibilityTarget,
        value: str,
    ) -> None:
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
    async def pinch(
        self,
        center_x: float,
        center_y: float,
        scale: float,
        duration: float = 0.5,
        radius: float = 100.0,
    ) -> None: ...

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
        # pyrefly: ignore [invalid-yield]
        yield


class ClientManager:
    @abstractmethod
    async def connect(
        self,
        destination: ConnectionDestination,
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

    @property
    @abstractmethod
    def ports(self) -> dict[str, str]:
        pass
