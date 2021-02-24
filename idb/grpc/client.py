#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import functools
import inspect
import logging
import os
import shutil
import tempfile
import urllib.parse
from io import StringIO
from pathlib import Path
from typing import (
    Any,
    AsyncGenerator,
    AsyncIterable,
    AsyncIterator,
    Dict,
    Iterable,
    List,
    Optional,
    Set,
    Tuple,
)

import idb.common.plugin as plugin
from grpclib.client import Channel
from grpclib.exceptions import GRPCError, ProtocolError, StreamTerminatedError
from idb.common.constants import TESTS_POLL_INTERVAL
from idb.common.file import drain_to_file
from idb.common.gzip import drain_gzip_decompress
from idb.common.hid import (
    button_press_to_events,
    iterator_to_async_iterator,
    key_press_to_events,
    swipe_to_events,
    tap_to_events,
    text_to_events,
)
from idb.common.logging import log_call
from idb.common.stream import stream_map
from idb.common.tar import create_tar, drain_untar, generate_tar
from idb.common.types import (
    AccessibilityInfo,
    Address,
    AppProcessState,
    Client as ClientBase,
    Companion,
    CompanionInfo,
    CrashLog,
    CrashLogInfo,
    CrashLogQuery,
    DomainSocketAddress,
    FileContainer,
    FileEntryInfo,
    FileListing,
    HIDButtonType,
    HIDEvent,
    IdbConnectionException,
    IdbException,
    InstalledAppInfo,
    InstalledArtifact,
    InstalledTestInfo,
    InstrumentsTimings,
    OnlyFilter,
    Permission,
    TargetDescription,
    TCPAddress,
    TestRunInfo,
    VideoFormat,
)
from idb.grpc.crash import (
    _to_crash_log,
    _to_crash_log_info_list,
    _to_crash_log_query_proto,
)
from idb.grpc.file import container_to_grpc as file_container_to_grpc
from idb.grpc.hid import event_to_grpc
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import (
    AccessibilityInfoRequest,
    AddMediaRequest,
    ApproveRequest,
    ClearKeychainRequest,
    ConnectRequest,
    ContactsUpdateRequest,
    CrashShowRequest,
    DebugServerRequest,
    DebugServerResponse,
    FocusRequest,
    InstallRequest,
    InstrumentsRunRequest,
    LaunchRequest,
    ListAppsRequest,
    Location,
    LogRequest,
    LsRequest,
    GetSettingRequest,
    LOCALE as LocaleSetting,
    ListSettingRequest,
    MkdirRequest,
    MvRequest,
    OpenUrlRequest,
    Payload,
    Point,
    PullRequest,
    PushRequest,
    RecordRequest,
    RmRequest,
    ScreenshotRequest,
    SetLocationRequest,
    SettingRequest,
    TargetDescriptionRequest,
    TerminateRequest,
    UninstallRequest,
    VideoStreamRequest,
    XctestListBundlesRequest,
    XctestListTestsRequest,
    XctraceRecordRequest,
)
from idb.grpc.install import (
    Bundle,
    Destination,
    generate_binary_chunks,
    generate_io_chunks,
    generate_requests,
)
from idb.grpc.instruments import (
    instruments_drain_until_running,
    instruments_generate_bytes,
    translate_instruments_timings,
)
from idb.grpc.launch import drain_launch_stream, end_launch_stream
from idb.grpc.stream import (
    cancel_wrapper,
    drain_to_stream,
    generate_bytes,
    stop_wrapper,
)
from idb.grpc.target import companion_to_py, target_to_py
from idb.grpc.video import generate_video_bytes
from idb.grpc.xctest import (
    make_request,
    make_results,
    save_attachments,
    write_result_bundle,
)
from idb.grpc.xctest_log_parser import XCTestLogParser
from idb.grpc.xctrace import (
    xctrace_drain_until_running,
    xctrace_generate_bytes,
)
from idb.utils.contextlib import asynccontextmanager


APPROVE_MAP: Dict[Permission, "ApproveRequest.Permission"] = {
    Permission.PHOTOS: ApproveRequest.PHOTOS,
    Permission.CAMERA: ApproveRequest.CAMERA,
    Permission.CONTACTS: ApproveRequest.CONTACTS,
    Permission.URL: ApproveRequest.URL,
    Permission.LOCATION: ApproveRequest.LOCATION,
    Permission.NOTIFICATION: ApproveRequest.NOTIFICATION,
}

VIDEO_FORMAT_MAP: Dict[VideoFormat, "VideoStreamRequest.Format"] = {
    VideoFormat.H264: VideoStreamRequest.H264,
    VideoFormat.RBGA: VideoStreamRequest.RBGA,
    VideoFormat.MJPEG: VideoStreamRequest.MJPEG,
    VideoFormat.MINICAP: VideoStreamRequest.MINICAP,
}


def log_and_handle_exceptions(func):  # pyre-ignore
    @functools.wraps(func)
    @log_call(name=func.__name__)
    async def func_wrapper(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
        try:
            return await func(*args, **kwargs)
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e
        except OSError as e:
            raise IdbConnectionException(e.strerror)

    @functools.wraps(func)
    @log_call(name=func.__name__)
    # pyre-fixme[53]: Captured variable `func` is not annotated.
    # pyre-fixme[3]: Return annotation cannot be `Any`.
    async def func_wrapper_gen(*args: Any, **kwargs: Any) -> Any:
        try:
            async for item in func(*args, **kwargs):
                yield item
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e
        except OSError as e:
            raise IdbConnectionException(e.strerror)

    if inspect.isasyncgenfunction(func):
        return func_wrapper_gen
    else:
        return func_wrapper


class Client(ClientBase):
    def __init__(
        self,
        stub: CompanionServiceStub,
        companion: CompanionInfo,
        logger: logging.Logger,
    ) -> None:
        self.stub = stub
        self.companion = companion
        self.logger = logger

    @property
    def address(self) -> Address:
        return self.companion.address

    @property
    def is_local(self) -> bool:
        return self.companion.is_local

    @classmethod
    @asynccontextmanager
    async def build(
        cls,
        address: Address,
        logger: logging.Logger,
        is_local: Optional[bool] = None,
        exchange_metadata: bool = True,
        extra_metadata: Optional[Dict[str, str]] = None,
    ) -> AsyncGenerator["Client", None]:
        metadata_to_companion = (
            {
                **{
                    key: value
                    for (key, value) in plugin.resolve_metadata(logger=logger).items()
                    if isinstance(value, str)
                },
                **(extra_metadata or {}),
            }
            if exchange_metadata
            else {}
        )
        async with (
            Channel(host=address.host, port=address.port, loop=asyncio.get_event_loop())
            if isinstance(address, TCPAddress)
            else Channel(path=address.path, loop=asyncio.get_event_loop())
        ) as channel:
            stub = CompanionServiceStub(channel=channel)
            with tempfile.NamedTemporaryFile(mode="w+b") as f:
                try:
                    response = await stub.connect(
                        ConnectRequest(
                            metadata=metadata_to_companion, local_file_path=f.name
                        )
                    )
                except Exception as ex:
                    raise IdbException(
                        f"Failed to connect to companion at address {address}: {ex}"
                    )
            companion = companion_to_py(
                companion=response.companion, address=address, is_local=is_local
            )
            if exchange_metadata:
                metadata_from_companion = {
                    key: value
                    for (key, value) in companion.metadata.items()
                    if isinstance(value, str)
                }
                plugin.append_companion_metadata(
                    logger=logger, metadata=metadata_from_companion
                )
            yield Client(stub=stub, companion=companion, logger=logger)

    @classmethod
    @asynccontextmanager
    async def for_companion(
        cls,
        companion: Companion,
        udid: str,
        logger: logging.Logger,
        only: Optional[OnlyFilter] = None,
    ) -> AsyncGenerator["Client", None]:
        with tempfile.NamedTemporaryFile() as temp:
            # Remove the tempfile so we can bind to it first.
            os.remove(temp.name)
            async with companion.unix_domain_server(
                udid=udid, path=temp.name, only=only
            ) as resolved_path, Client.build(
                address=DomainSocketAddress(path=resolved_path),
                is_local=True,
                logger=logger,
            ) as client:
                yield client

    async def _tail_specific_logs(
        self,
        source: LogRequest.Source,
        stop: asyncio.Event,
        arguments: Optional[List[str]],
    ) -> AsyncIterator[str]:
        async with self.stub.log.open() as stream:
            await stream.send_message(
                LogRequest(arguments=arguments, source=source), end=True
            )
            async for message in cancel_wrapper(stream=stream, stop=stop):
                yield message.output.decode()

    async def _install_to_destination(
        self, bundle: Bundle, destination: Destination
    ) -> AsyncIterator[InstalledArtifact]:
        async with self.stub.install.open() as stream:
            generator = None
            if isinstance(bundle, str):
                url = urllib.parse.urlparse(bundle)
                if url.scheme:
                    # send url
                    payload = Payload(url=bundle)
                    generator = generate_requests([InstallRequest(payload=payload)])

                else:
                    file_path = str(Path(bundle).resolve(strict=True))
                    if self.is_local:
                        # send file_path
                        generator = generate_requests(
                            [InstallRequest(payload=Payload(file_path=file_path))]
                        )
                    else:
                        # chunk file from file_path
                        generator = generate_binary_chunks(
                            path=file_path, destination=destination, logger=self.logger
                        )

            else:
                # chunk file from memory
                generator = generate_io_chunks(io=bundle, logger=self.logger)
                # stream to companion
            await stream.send_message(InstallRequest(destination=destination))
            async for message in generator:
                await stream.send_message(message)
            await stream.end()
            async for response in stream:
                yield InstalledArtifact(
                    name=response.name, uuid=response.uuid, progress=response.progress
                )

    @property
    def _is_verbose(self) -> bool:
        return self.logger.isEnabledFor(logging.DEBUG)

    def _log_from_companion(self, data: str) -> None:
        self.logger.info(data.strip())

    @log_and_handle_exceptions
    async def list_apps(
        self, fetch_process_state: bool = True
    ) -> List[InstalledAppInfo]:
        response = await self.stub.list_apps(
            ListAppsRequest(suppress_process_state=fetch_process_state is False)
        )
        return [
            InstalledAppInfo(
                bundle_id=app.bundle_id,
                name=app.name,
                architectures=app.architectures,
                install_type=app.install_type,
                process_state=AppProcessState(app.process_state),
                debuggable=app.debuggable,
            )
            for app in response.apps
        ]

    @log_and_handle_exceptions
    async def accessibility_info(
        self, point: Optional[Tuple[int, int]], nested: bool
    ) -> AccessibilityInfo:
        grpc_point = Point(x=point[0], y=point[1]) if point is not None else None
        response = await self.stub.accessibility_info(
            AccessibilityInfoRequest(
                point=grpc_point,
                format=(
                    AccessibilityInfoRequest.NESTED
                    if nested
                    else AccessibilityInfoRequest.LEGACY
                ),
            )
        )
        return AccessibilityInfo(json=response.json)

    @log_and_handle_exceptions
    async def add_media(self, file_paths: List[str]) -> None:
        async with self.stub.add_media.open() as stream:
            if self.is_local:
                for file_path in file_paths:
                    await stream.send_message(
                        AddMediaRequest(payload=Payload(file_path=file_path))
                    )
                await stream.end()
                await stream.recv_message()
            else:
                self.logger.info(f"Adding media from {file_paths}")
                generator = stream_map(
                    generate_tar(
                        paths=file_paths,
                        place_in_subfolders=True,
                        verbose=self._is_verbose,
                    ),
                    lambda chunk: AddMediaRequest(payload=Payload(data=chunk)),
                )
                await drain_to_stream(
                    stream=stream, generator=generator, logger=self.logger
                )

    @log_and_handle_exceptions
    async def approve(
        self, bundle_id: str, permissions: Set[Permission], scheme: Optional[str] = None
    ) -> None:
        await self.stub.approve(
            ApproveRequest(
                bundle_id=bundle_id,
                permissions=[APPROVE_MAP[permission] for permission in permissions],
                scheme=scheme,
            )
        )

    @log_and_handle_exceptions
    async def clear_keychain(self) -> None:
        await self.stub.clear_keychain(ClearKeychainRequest())

    @log_and_handle_exceptions
    async def contacts_update(self, contacts_path: str) -> None:
        data = await create_tar([contacts_path])
        await self.stub.contacts_update(
            ContactsUpdateRequest(payload=Payload(data=data))
        )

    @log_and_handle_exceptions
    async def screenshot(self) -> bytes:
        response = await self.stub.screenshot(ScreenshotRequest())
        return response.image_data

    @log_and_handle_exceptions
    async def set_location(self, latitude: float, longitude: float) -> None:
        await self.stub.set_location(
            SetLocationRequest(
                location=Location(latitude=latitude, longitude=longitude)
            )
        )

    @log_and_handle_exceptions
    async def terminate(self, bundle_id: str) -> None:
        await self.stub.terminate(TerminateRequest(bundle_id=bundle_id))

    @log_and_handle_exceptions
    async def describe(self, fetch_diagnostics: bool = False) -> TargetDescription:
        response = await self.stub.describe(
            TargetDescriptionRequest(fetch_diagnostics=fetch_diagnostics)
        )
        target = response.target_description
        return target_to_py(
            target=target,
            # Use the local understanding of the companion instead of the remote's.
            companion=CompanionInfo(
                address=self.address, udid=target.udid, is_local=self.is_local
            ),
            # Extract the companion metadata from the response.
            metadata=response.companion.metadata,
        )

    @log_and_handle_exceptions
    async def focus(self) -> None:
        await self.stub.focus(FocusRequest())

    @log_and_handle_exceptions
    async def open_url(self, url: str) -> None:
        await self.stub.open_url(OpenUrlRequest(url=url))

    @log_and_handle_exceptions
    async def uninstall(self, bundle_id: str) -> None:
        await self.stub.uninstall(UninstallRequest(bundle_id=bundle_id))

    @log_and_handle_exceptions
    async def rm(self, container: FileContainer, paths: List[str]) -> None:
        await self.stub.rm(
            RmRequest(paths=paths, container=file_container_to_grpc(container))
        )

    @log_and_handle_exceptions
    async def mv(
        self, container: FileContainer, src_paths: List[str], dest_path: str
    ) -> None:
        await self.stub.mv(
            MvRequest(
                src_paths=src_paths,
                dst_path=dest_path,
                container=file_container_to_grpc(container),
            )
        )

    @log_and_handle_exceptions
    async def ls_single(
        self, container: FileContainer, path: str
    ) -> List[FileEntryInfo]:
        response = await self.stub.ls(
            LsRequest(path=path, container=file_container_to_grpc(container))
        )
        return [FileEntryInfo(path=file.path) for file in response.files]

    @log_and_handle_exceptions
    async def ls(self, container: FileContainer, paths: List[str]) -> List[FileListing]:
        response = await self.stub.ls(
            LsRequest(paths=paths, container=file_container_to_grpc(container))
        )
        return [
            FileListing(
                parent=listing.parent.path,
                entries=[FileEntryInfo(path=entry.path) for entry in listing.files],
            )
            for listing in response.listings
        ]

    @log_and_handle_exceptions
    async def mkdir(self, container: FileContainer, path: str) -> None:
        await self.stub.mkdir(
            MkdirRequest(path=path, container=file_container_to_grpc(container))
        )

    @log_and_handle_exceptions
    async def crash_delete(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        response = await self.stub.crash_delete(_to_crash_log_query_proto(query))
        return _to_crash_log_info_list(response)

    @log_and_handle_exceptions
    async def crash_list(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        response = await self.stub.crash_list(_to_crash_log_query_proto(query))
        return _to_crash_log_info_list(response)

    @log_and_handle_exceptions
    async def crash_show(self, name: str) -> CrashLog:
        response = await self.stub.crash_show(CrashShowRequest(name=name))
        return _to_crash_log(response)

    @log_and_handle_exceptions
    async def install(self, bundle: Bundle) -> AsyncIterator[InstalledArtifact]:
        async for response in self._install_to_destination(
            bundle=bundle, destination=InstallRequest.APP
        ):
            yield response

    @log_and_handle_exceptions
    async def install_xctest(self, xctest: Bundle) -> AsyncIterator[InstalledArtifact]:
        async for response in self._install_to_destination(
            bundle=xctest, destination=InstallRequest.XCTEST
        ):
            yield response

    @log_and_handle_exceptions
    async def install_dylib(self, dylib: Bundle) -> AsyncIterator[InstalledArtifact]:
        async for response in self._install_to_destination(
            bundle=dylib, destination=InstallRequest.DYLIB
        ):
            yield response

    @log_and_handle_exceptions
    async def install_dsym(self, dsym: Bundle) -> AsyncIterator[InstalledArtifact]:
        async for response in self._install_to_destination(
            bundle=dsym, destination=InstallRequest.DSYM
        ):
            yield response

    @log_and_handle_exceptions
    async def install_framework(
        self, framework_path: Bundle
    ) -> AsyncIterator[InstalledArtifact]:
        async for response in self._install_to_destination(
            bundle=framework_path, destination=InstallRequest.FRAMEWORK
        ):
            yield response

    @log_and_handle_exceptions
    async def push(
        self, src_paths: List[str], container: FileContainer, dest_path: str
    ) -> None:
        async with self.stub.push.open() as stream:
            await stream.send_message(
                PushRequest(
                    inner=PushRequest.Inner(
                        dst_path=dest_path, container=file_container_to_grpc(container)
                    )
                )
            )
            if self.is_local:
                for src_path in src_paths:
                    await stream.send_message(
                        PushRequest(payload=Payload(file_path=src_path))
                    )
                await stream.end()
                await stream.recv_message()
            else:
                await drain_to_stream(
                    stream=stream,
                    generator=stream_map(
                        generate_tar(paths=src_paths, verbose=self._is_verbose),
                        lambda chunk: PushRequest(payload=Payload(data=chunk)),
                    ),
                    logger=self.logger,
                )

    @log_and_handle_exceptions
    async def pull(
        self, container: FileContainer, src_path: str, dest_path: str
    ) -> None:
        async with self.stub.pull.open() as stream:
            request = request = PullRequest(
                src_path=src_path,
                # not sending the destination to remote companion
                # so it streams the file back
                dst_path=dest_path if self.is_local else None,
                container=file_container_to_grpc(container),
            )
            await stream.send_message(request)
            await stream.end()
            if self.is_local:
                await stream.recv_message()
            else:
                await drain_untar(generate_bytes(stream), output_path=dest_path)
            self.logger.info(f"pulled file to {dest_path}")

    @log_and_handle_exceptions
    async def list_test_bundle(self, test_bundle_id: str, app_path: str) -> List[str]:
        response = await self.stub.xctest_list_tests(
            XctestListTestsRequest(bundle_name=test_bundle_id, app_path=app_path)
        )
        return list(response.names)

    @log_and_handle_exceptions
    async def list_xctests(self) -> List[InstalledTestInfo]:
        response = await self.stub.xctest_list_bundles(XctestListBundlesRequest())
        return [
            InstalledTestInfo(
                bundle_id=bundle.bundle_id,
                name=bundle.name,
                architectures=bundle.architectures,
            )
            for bundle in response.bundles
        ]

    @log_and_handle_exceptions
    async def send_events(self, events: Iterable[HIDEvent]) -> None:
        await self.hid(iterator_to_async_iterator(events))

    @log_and_handle_exceptions
    async def tap(self, x: float, y: float, duration: Optional[float] = None) -> None:
        await self.send_events(tap_to_events(x, y, duration))

    @log_and_handle_exceptions
    async def button(
        self, button_type: HIDButtonType, duration: Optional[float] = None
    ) -> None:
        await self.send_events(button_press_to_events(button_type, duration))

    @log_and_handle_exceptions
    async def key(self, keycode: int, duration: Optional[float] = None) -> None:
        await self.send_events(key_press_to_events(keycode, duration))

    @log_and_handle_exceptions
    async def text(self, text: str) -> None:
        await self.send_events(text_to_events(text))

    @log_and_handle_exceptions
    async def swipe(
        self,
        p_start: Tuple[int, int],
        p_end: Tuple[int, int],
        duration: Optional[float] = None,
        delta: Optional[int] = None,
    ) -> None:
        await self.send_events(swipe_to_events(p_start, p_end, duration, delta))

    @log_and_handle_exceptions
    async def key_sequence(self, key_sequence: List[int]) -> None:
        events: List[HIDEvent] = []
        for key in key_sequence:
            events.extend(key_press_to_events(key))
        await self.send_events(events)

    @log_and_handle_exceptions
    async def hid(self, event_iterator: AsyncIterable[HIDEvent]) -> None:
        async with self.stub.hid.open() as stream:
            grpc_event_iterator = (
                event_to_grpc(event) async for event in event_iterator
            )
            await drain_to_stream(
                stream=stream,
                # pyre-fixme[6]: Expected
                #  `AsyncIterator[Variable[idb.grpc.stream._TSend]]` for 2nd param but
                #  got `Generator[typing.Any, None, None]`.
                generator=grpc_event_iterator,
                logger=self.logger,
            )
            await stream.recv_message()

    @log_and_handle_exceptions
    async def debug_server(self, request: DebugServerRequest) -> DebugServerResponse:
        async with self.stub.debugserver.open() as stream:
            await stream.send_message(request)
            await stream.end()
            return await stream.recv_message()

    @log_and_handle_exceptions
    async def debugserver_start(self, bundle_id: str) -> List[str]:
        response = await self.debug_server(
            request=DebugServerRequest(
                start=DebugServerRequest.Start(bundle_id=bundle_id)
            )
        )
        return response.status.lldb_bootstrap_commands

    @log_and_handle_exceptions
    async def debugserver_stop(self) -> None:
        await self.debug_server(
            request=DebugServerRequest(stop=DebugServerRequest.Stop())
        )

    @log_and_handle_exceptions
    async def debugserver_status(self) -> Optional[List[str]]:
        response = await self.debug_server(
            request=DebugServerRequest(status=DebugServerRequest.Status())
        )
        commands = response.status.lldb_bootstrap_commands
        return commands if commands else None

    @log_and_handle_exceptions
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
        self.logger.info("Starting instruments connection")
        async with self.stub.instruments_run.open() as stream:
            self.logger.info("Sending instruments request")
            await stream.send_message(
                InstrumentsRunRequest(
                    start=InstrumentsRunRequest.Start(
                        template_name=template_name,
                        app_bundle_id=app_bundle_id,
                        environment=app_environment,
                        arguments=app_arguments,
                        tool_arguments=tool_arguments,
                        timings=translate_instruments_timings(timings),
                    )
                )
            )
            self.logger.info("Starting instruments")
            await instruments_drain_until_running(stream=stream, logger=self.logger)
            if started:
                started.set()
            self.logger.info("Instruments has started, waiting for stop")
            async for response in stop_wrapper(stream=stream, stop=stop):
                output = response.log_output
                if len(output):
                    self.logger.info(output.decode())
            self.logger.info("Stopping instruments")
            await stream.send_message(
                InstrumentsRunRequest(
                    stop=InstrumentsRunRequest.Stop(
                        post_process_arguments=post_process_arguments
                    )
                )
            )
            await stream.end()

            result = []

            with tempfile.TemporaryDirectory() as tmp_trace_dir:
                self.logger.info(
                    f"Writing instruments data from tar to {tmp_trace_dir}"
                )
                await drain_untar(
                    instruments_generate_bytes(stream=stream, logger=self.logger),
                    output_path=tmp_trace_dir,
                )

                if os.path.exists(
                    os.path.join(os.path.abspath(tmp_trace_dir), "instrument_data")
                ):
                    # tar is an instruments trace (old behavior)
                    trace_file = f"{trace_basename}.trace"
                    shutil.copytree(tmp_trace_dir, trace_file)
                    result.append(trace_file)
                    self.logger.info(f"Trace written to {trace_file}")
                else:
                    # tar is a folder containing one or more trace files
                    for file in os.listdir(tmp_trace_dir):
                        _, file_extension = os.path.splitext(file)
                        tmp_trace_file = os.path.join(
                            os.path.abspath(tmp_trace_dir), file
                        )
                        trace_file = f"{trace_basename}{file_extension}"
                        shutil.move(tmp_trace_file, trace_file)
                        result.append(trace_file)
                        self.logger.info(f"Trace written to {trace_file}")

            return result

    @log_and_handle_exceptions
    async def launch(
        self,
        bundle_id: str,
        args: Optional[List[str]] = None,
        env: Optional[Dict[str, str]] = None,
        foreground_if_running: bool = False,
        wait_for_debugger: bool = False,
        stop: Optional[asyncio.Event] = None,
    ) -> None:
        async with self.stub.launch.open() as stream:
            request = LaunchRequest(
                start=LaunchRequest.Start(
                    bundle_id=bundle_id,
                    env=env,
                    app_args=args,
                    foreground_if_running=foreground_if_running,
                    wait_for_debugger=wait_for_debugger,
                    wait_for=True if stop else False,
                )
            )
            await stream.send_message(request)
            if stop:
                await asyncio.gather(
                    drain_launch_stream(stream), end_launch_stream(stream, stop)
                )
            else:
                await stream.end()
                await drain_launch_stream(stream)

    @log_and_handle_exceptions
    async def record_video(self, stop: asyncio.Event, output_file: str) -> None:
        self.logger.info("Starting connection to backend")
        async with self.stub.record.open() as stream:
            if self.is_local:
                self.logger.info(
                    f"Starting video recording to local file {output_file}"
                )
                await stream.send_message(
                    RecordRequest(start=RecordRequest.Start(file_path=output_file))
                )
            else:
                self.logger.info("Starting video recording with response data")
                await stream.send_message(
                    RecordRequest(start=RecordRequest.Start(file_path=None))
                )
            await stop.wait()
            self.logger.info("Stopping video recording")
            await stream.send_message(RecordRequest(stop=RecordRequest.Stop()))
            await stream.end()
            if self.is_local:
                self.logger.info("Video saved at output path")
                await stream.recv_message()
            else:
                self.logger.info(f"Decompressing gzip to {output_file}")
                await drain_gzip_decompress(
                    generate_video_bytes(stream), output_path=output_file
                )
                self.logger.info(f"Finished decompression to {output_file}")

    async def stream_video(
        self,
        output_file: Optional[str],
        fps: Optional[int],
        format: VideoFormat,
        compression_quality: float,
        scale_factor: float = 1,
    ) -> AsyncGenerator[bytes, None]:
        self.logger.info("Starting connection to backend")
        async with self.stub.video_stream.open() as stream:
            if self.is_local and output_file:
                self.logger.info(
                    f"Streaming locally with companion writing to {output_file}"
                )
                await stream.send_message(
                    VideoStreamRequest(
                        start=VideoStreamRequest.Start(
                            file_path=output_file,
                            fps=fps,
                            format=VIDEO_FORMAT_MAP[format],
                            compression_quality=compression_quality,
                            scale_factor=scale_factor,
                        )
                    )
                )
            else:
                self.logger.info("Starting streaming over the wire")
                await stream.send_message(
                    VideoStreamRequest(
                        start=VideoStreamRequest.Start(
                            file_path=None,
                            fps=fps,
                            format=VIDEO_FORMAT_MAP[format],
                            compression_quality=compression_quality,
                            scale_factor=scale_factor,
                        )
                    )
                )
            try:
                iterator = generate_bytes(stream=stream, logger=self.logger)
                if output_file and not self.is_local:
                    self.logger.info(f"Writing wired bytes to {output_file}")
                    await drain_to_file(stream=iterator, file_path=output_file)
                else:
                    async for data in iterator:
                        yield data
            finally:
                self.logger.info("Stopping video streaming")
                await stream.send_message(
                    VideoStreamRequest(stop=VideoStreamRequest.Stop())
                )
                await stream.end()

    @log_and_handle_exceptions
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
        poll_interval_sec: float = TESTS_POLL_INTERVAL,
        report_activities: bool = False,
        report_attachments: bool = False,
        activities_output_path: Optional[str] = None,
        coverage_output_path: Optional[str] = None,
    ) -> AsyncIterator[TestRunInfo]:
        async with self.stub.xctest_run.open() as stream:
            request = make_request(
                test_bundle_id=test_bundle_id,
                app_bundle_id=app_bundle_id,
                test_host_app_bundle_id=test_host_app_bundle_id,
                is_ui_test=is_ui_test,
                is_logic_test=is_logic_test,
                tests_to_run=tests_to_run,
                tests_to_skip=tests_to_skip,
                env=env,
                args=args,
                result_bundle_path=result_bundle_path,
                timeout=timeout,
                report_activities=(
                    report_activities
                    or activities_output_path is not None
                    or report_attachments
                ),
                report_attachments=report_attachments,
                collect_coverage=coverage_output_path is not None,
            )
            log_parser = XCTestLogParser()
            await stream.send_message(request)
            await stream.end()
            async for response in stream:
                # response.log_output is a container of strings.
                # google.protobuf.pyext._message.RepeatedScalarContainer.
                for line in [
                    line
                    for lines in response.log_output
                    for line in lines.splitlines(keepends=True)
                ]:
                    log_parser.parse_streaming_log(line.rstrip())
                    self._log_from_companion(line)
                    if idb_log_buffer:
                        idb_log_buffer.write(line)

                if result_bundle_path:
                    await write_result_bundle(
                        response=response,
                        output_path=result_bundle_path,
                        logger=self.logger,
                    )
                if response.coverage_json and coverage_output_path:
                    with open(coverage_output_path, "w") as f:
                        f.write(response.coverage_json)
                for result in make_results(response, log_parser):
                    if activities_output_path:
                        save_attachments(
                            run_info=result,
                            activities_output_path=activities_output_path,
                        )
                    yield result

    @log_and_handle_exceptions
    async def tail_logs(
        self, stop: asyncio.Event, arguments: Optional[List[str]] = None
    ) -> AsyncIterator[str]:
        async for message in self._tail_specific_logs(
            source=LogRequest.TARGET, stop=stop, arguments=arguments
        ):
            yield message

    @log_and_handle_exceptions
    async def tail_companion_logs(self, stop: asyncio.Event) -> AsyncIterator[str]:
        async for message in self._tail_specific_logs(
            source=LogRequest.COMPANION, stop=stop, arguments=None
        ):
            yield message

    @log_and_handle_exceptions
    async def set_hardware_keyboard(self, enabled: bool) -> None:
        await self.stub.setting(
            SettingRequest(
                hardwareKeyboard=SettingRequest.HardwareKeyboard(enabled=enabled)
            )
        )

    @log_and_handle_exceptions
    async def set_locale(self, locale_identifier: str) -> None:
        await self.stub.setting(
            SettingRequest(
                stringSetting=SettingRequest.StringSetting(
                    setting=LocaleSetting, value=locale_identifier
                )
            )
        )

    @log_and_handle_exceptions
    async def get_locale(self) -> str:
        response = await self.stub.get_setting(GetSettingRequest(setting=LocaleSetting))
        return response.value

    @log_and_handle_exceptions
    async def list_locale_identifiers(self) -> List[str]:
        response = await self.stub.list_settings(
            ListSettingRequest(
                setting=LocaleSetting,
            )
        )
        return list(response.values)

    @log_and_handle_exceptions
    async def xctrace_record(
        self,
        stop: asyncio.Event,
        # original 'xctrace record' options
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
        # FB options
        post_args: Optional[List[str]] = None,
        stop_timeout: Optional[float] = None,
        # control events
        started: Optional[asyncio.Event] = None,
    ) -> List[str]:
        self.logger.info("Starting xctrace connection")
        async with self.stub.xctrace_record.open() as stream:
            self.logger.info("Sending xctrace record request")
            target = None
            if all_processes:
                target = XctraceRecordRequest.Target(all_processes=all_processes)
            elif process_to_attach:
                target = XctraceRecordRequest.Target(
                    process_to_attach=process_to_attach
                )
            else:
                target = XctraceRecordRequest.Target(
                    launch_process=XctraceRecordRequest.LauchProcess(
                        process_to_launch=process_to_launch,
                        launch_args=launch_args,
                        target_stdin=target_stdin,
                        target_stdout=target_stdout,
                        process_env=process_env,
                    )
                )
            await stream.send_message(
                XctraceRecordRequest(
                    start=XctraceRecordRequest.Start(
                        template_name=template_name,
                        time_limit=time_limit,
                        package=package,
                        target=target,
                    )
                )
            )
            self.logger.info("Starting xctrace record")
            await xctrace_drain_until_running(stream=stream, logger=self.logger)
            if started:
                started.set()
            self.logger.info("Xctrace record has started, waiting for stop")
            async for response in stop_wrapper(stream=stream, stop=stop):
                log = response.log
                if len(log):
                    self.logger.info(log.decode())
            self.logger.info("Stopping xctrace record")
            await stream.send_message(
                XctraceRecordRequest(
                    stop=XctraceRecordRequest.Stop(
                        timeout=stop_timeout,
                        args=post_args,
                    )
                )
            )
            await stream.end()

            result = []

            with tempfile.TemporaryDirectory() as tmp_trace_dir:
                self.logger.info(f"Writing xctrace data from tar to {tmp_trace_dir}")
                await drain_untar(
                    xctrace_generate_bytes(stream=stream, logger=self.logger),
                    output_path=tmp_trace_dir,
                )
                if os.path.exists(
                    os.path.join(os.path.abspath(tmp_trace_dir), "instrument_data")
                ):
                    trace_file = f"{output}.trace"
                    shutil.copytree(tmp_trace_dir, trace_file)
                    result.append(trace_file)
                    self.logger.info(f"Trace written to {trace_file}")
                else:
                    # tar is a folder containing one or more trace files
                    for file in os.listdir(tmp_trace_dir):
                        _, file_extension = os.path.splitext(file)
                        tmp_trace_file = os.path.join(
                            os.path.abspath(tmp_trace_dir), file
                        )
                        trace_file = f"{output}{file_extension}"
                        shutil.move(tmp_trace_file, trace_file)
                        result.append(trace_file)
                        self.logger.info(f"Trace written to {trace_file}")

            return result
