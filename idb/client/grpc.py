#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import functools
import inspect
import logging
import os
import urllib.parse
from io import StringIO
from pathlib import Path
from sys import platform
from typing import (
    Any,
    AsyncIterable,
    AsyncIterator,
    Dict,
    Iterable,
    List,
    Optional,
    Set,
    Tuple,
)

from grpclib.client import Channel
from grpclib.exceptions import GRPCError, ProtocolError, StreamTerminatedError
from idb.client.pid_saver import PidSaver
from idb.common.companion_spawner import CompanionSpawner
from idb.common.constants import TESTS_POLL_INTERVAL
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.gzip import drain_gzip_decompress
from idb.common.hid import (
    button_press_to_events,
    iterator_to_async_iterator,
    key_press_to_events,
    swipe_to_events,
    tap_to_events,
    text_to_events,
)
from idb.common.install import (
    Bundle,
    Destination,
    generate_binary_chunks,
    generate_io_chunks,
    generate_requests,
)
from idb.common.instruments import (
    drain_until_running,
    instruments_generate_bytes,
    translate_instruments_timings,
)
from idb.common.launch import drain_launch_stream, end_launch_stream
from idb.common.local_targets_manager import LocalTargetsManager
from idb.common.logging import log_call
from idb.common.stream import stream_map
from idb.common.tar import create_tar, drain_untar, generate_tar
from idb.common.types import (
    AccessibilityInfo,
    Address,
    AppProcessState,
    CompanionInfo,
    ConnectionDestination,
    CrashLog,
    CrashLogInfo,
    CrashLogQuery,
    FileEntryInfo,
    HIDButtonType,
    HIDEvent,
    IdbClient,
    IdbException,
    InstalledAppInfo,
    InstalledArtifact,
    InstalledTestInfo,
    InstrumentsTimings,
    LoggingMetadata,
    TargetDescription,
    TestRunInfo,
)
from idb.common.video import generate_video_bytes
from idb.common.xctest import make_request, make_results, write_result_bundle
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
    MkdirRequest,
    MvRequest,
    OpenUrlRequest,
    Payload,
    Point,
    PullRequest,
    PullResponse,
    PushRequest,
    RecordRequest,
    RmRequest,
    ScreenshotRequest,
    SetLocationRequest,
    TargetDescriptionRequest,
    TerminateRequest,
    UninstallRequest,
    XctestListBundlesRequest,
    XctestListTestsRequest,
)
from idb.grpc.stream import (
    cancel_wrapper,
    drain_to_stream,
    generate_bytes,
    stop_wrapper,
)
from idb.ipc.mapping.crash import (
    _to_crash_log,
    _to_crash_log_info_list,
    _to_crash_log_query_proto,
)
from idb.ipc.mapping.destination import destination_to_grpc
from idb.ipc.mapping.hid import event_to_grpc
from idb.ipc.mapping.target import target_to_py
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


APPROVE_MAP: Dict[str, Any] = {
    "photos": ApproveRequest.PHOTOS,
    "camera": ApproveRequest.CAMERA,
    "contacts": ApproveRequest.CONTACTS,
}


CLIENT_METADATA: LoggingMetadata = {"component": "client", "rpc_protocol": "grpc"}


def log_and_handle_exceptions(func):  # pyre-ignore
    @functools.wraps(func)
    @log_call(name=func.__name__, metadata=CLIENT_METADATA)
    async def func_wrapper(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
        try:
            return await func(*args, **kwargs)
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    @functools.wraps(func)
    @log_call(name=func.__name__, metadata=CLIENT_METADATA)
    async def func_wrapper_gen(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
        try:
            async for item in func(*args, **kwargs):
                yield item
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    if inspect.isasyncgenfunction(func):
        return func_wrapper_gen
    else:
        return func_wrapper


class GrpcClient(IdbClient):
    def __init__(
        self, target_udid: Optional[str], logger: Optional[logging.Logger] = None
    ) -> None:
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_grpc_client")
        )
        self.target_udid = target_udid
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)
        self.local_targets_manager = LocalTargetsManager(logger=self.logger)
        self.companion_info: Optional[CompanionInfo] = None

    async def spawn_notifier(self) -> None:
        if platform == "darwin":
            companion_spawner = CompanionSpawner(
                companion_path="idb_companion", logger=self.logger
            )
            await companion_spawner.spawn_notifier()

    @asynccontextmanager
    async def get_stub(self) -> CompanionServiceStub:
        await self.spawn_notifier()
        channel: Optional[Channel] = None
        try:
            try:
                self.companion_info = self.direct_companion_manager.get_companion_info(
                    target_udid=self.target_udid
                )
            except IdbException as e:
                # will try to spawn a companion if on mac.
                companion_info = await self.spawn_companion(
                    target_udid=none_throws(self.target_udid)
                )
                if companion_info:
                    self.companion_info = companion_info
                else:
                    raise e
            self.logger.info(f"using companion {self.companion_info}")
            channel = Channel(
                self.companion_info.host,
                self.companion_info.port,
                loop=asyncio.get_event_loop(),
            )
            yield CompanionServiceStub(channel=channel)
        finally:
            if channel:
                channel.close()

    async def spawn_companion(self, target_udid: str) -> Optional[CompanionInfo]:
        if self.local_targets_manager.is_local_target_available(
            target_udid=target_udid
        ):
            companion_spawner = CompanionSpawner(
                companion_path="idb_companion", logger=self.logger
            )
            self.logger.info(f"will attempt to spawn a companion for {target_udid}")
            port = await companion_spawner.spawn_companion(target_udid=target_udid)
            if port:
                self.logger.info(f"spawned a companion for {target_udid}")
                host = "localhost"
                companion_info = CompanionInfo(
                    host=host, port=port, udid=target_udid, is_local=True
                )
                self.direct_companion_manager.add_companion(companion_info)
                return companion_info
        return None

    @property
    def metadata(self) -> Dict[str, str]:
        if self.target_udid:
            return {"udid": self.target_udid}
        else:
            return {}

    async def kill(self) -> None:
        self.direct_companion_manager.clear()
        self.local_targets_manager.clear()
        PidSaver(logger=self.logger).kill_saved_pids()

    @log_and_handle_exceptions
    async def list_apps(self) -> List[InstalledAppInfo]:
        async with self.get_stub() as stub:
            response = await stub.list_apps(ListAppsRequest())
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
        self, point: Optional[Tuple[int, int]]
    ) -> AccessibilityInfo:
        async with self.get_stub() as stub:
            grpc_point = Point(x=point[0], y=point[1]) if point is not None else None
            response = await stub.accessibility_info(
                AccessibilityInfoRequest(point=grpc_point)
            )
            return AccessibilityInfo(json=response.json)

    @log_and_handle_exceptions
    async def add_media(self, file_paths: List[str]) -> None:
        async with self.get_stub() as stub, stub.add_media.open() as stream:
            if none_throws(self.companion_info).is_local:
                for file_path in file_paths:
                    await stream.send_message(
                        AddMediaRequest(payload=Payload(file_path=file_path))
                    )
                await stream.end()
                await stream.recv_message()
            else:
                generator = stream_map(
                    generate_tar(paths=file_paths, place_in_subfolders=True),
                    lambda chunk: AddMediaRequest(payload=Payload(data=chunk)),
                )
                await drain_to_stream(
                    stream=stream, generator=generator, logger=self.logger
                )

    @log_and_handle_exceptions
    async def approve(self, bundle_id: str, permissions: Set[str]) -> None:
        async with self.get_stub() as stub:
            await stub.approve(
                ApproveRequest(
                    bundle_id=bundle_id,
                    permissions=[APPROVE_MAP[permission] for permission in permissions],
                )
            )

    @log_and_handle_exceptions
    async def clear_keychain(self) -> None:
        async with self.get_stub() as stub:
            await stub.clear_keychain(ClearKeychainRequest())

    @log_and_handle_exceptions
    async def contacts_update(self, contacts_path: str) -> None:
        async with self.get_stub() as stub:
            data = await create_tar([contacts_path])
            await stub.contacts_update(
                ContactsUpdateRequest(payload=Payload(data=data))
            )

    @log_and_handle_exceptions
    async def screenshot(self) -> bytes:
        async with self.get_stub() as stub:
            response = await stub.screenshot(ScreenshotRequest())
            return response.image_data

    @log_and_handle_exceptions
    async def set_location(self, latitude: float, longitude: float) -> None:
        async with self.get_stub() as stub:
            await stub.set_location(
                SetLocationRequest(
                    location=Location(latitude=latitude, longitude=longitude)
                )
            )

    @log_and_handle_exceptions
    async def terminate(self, bundle_id: str) -> None:
        async with self.get_stub() as stub:
            await stub.terminate(TerminateRequest(bundle_id=bundle_id))

    @log_and_handle_exceptions
    async def describe(self) -> TargetDescription:
        async with self.get_stub() as stub:
            response = await stub.describe(TargetDescriptionRequest())
            return target_to_py(response.target_description)

    @log_and_handle_exceptions
    async def focus(self) -> None:
        async with self.get_stub() as stub:
            await stub.focus(FocusRequest())

    @log_and_handle_exceptions
    async def open_url(self, url: str) -> None:
        async with self.get_stub() as stub:
            await stub.open_url(OpenUrlRequest(url=url))

    @log_and_handle_exceptions
    async def uninstall(self, bundle_id: str) -> None:
        async with self.get_stub() as stub:
            await stub.uninstall(UninstallRequest(bundle_id=bundle_id))

    @log_and_handle_exceptions
    async def rm(self, bundle_id: str, paths: List[str]) -> None:
        async with self.get_stub() as stub:
            await stub.rm(RmRequest(bundle_id=bundle_id, paths=paths))

    @log_and_handle_exceptions
    async def mv(self, bundle_id: str, src_paths: List[str], dest_path: str) -> None:
        async with self.get_stub() as stub:
            await stub.mv(
                MvRequest(bundle_id=bundle_id, src_paths=src_paths, dst_path=dest_path)
            )

    @log_and_handle_exceptions
    async def ls(self, bundle_id: str, path: str) -> List[FileEntryInfo]:
        async with self.get_stub() as stub:
            response = await stub.ls(LsRequest(bundle_id=bundle_id, path=path))
            return [FileEntryInfo(path=file.path) for file in response.files]

    @log_and_handle_exceptions
    async def mkdir(self, bundle_id: str, path: str) -> None:
        async with self.get_stub() as stub:
            await stub.mkdir(MkdirRequest(bundle_id=bundle_id, path=path))

    @log_and_handle_exceptions
    async def crash_delete(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        async with self.get_stub() as stub:
            response = await stub.crash_delete(_to_crash_log_query_proto(query))
            return _to_crash_log_info_list(response)

    @log_and_handle_exceptions
    async def crash_list(self, query: CrashLogQuery) -> List[CrashLogInfo]:
        async with self.get_stub() as stub:
            response = await stub.crash_list(_to_crash_log_query_proto(query))
            return _to_crash_log_info_list(response)

    @log_and_handle_exceptions
    async def crash_show(self, name: str) -> CrashLog:
        async with self.get_stub() as stub:
            response = await stub.crash_show(CrashShowRequest(name=name))
            return _to_crash_log(response)

    @log_and_handle_exceptions
    async def install(self, bundle: Bundle) -> InstalledArtifact:
        return await self._install_to_destination(
            bundle=bundle, destination=InstallRequest.APP
        )

    @log_and_handle_exceptions
    async def install_xctest(self, xctest: Bundle) -> InstalledArtifact:
        return await self._install_to_destination(
            bundle=xctest, destination=InstallRequest.XCTEST
        )

    @log_and_handle_exceptions
    async def install_dylib(self, dylib: Bundle) -> InstalledArtifact:
        return await self._install_to_destination(
            bundle=dylib, destination=InstallRequest.DYLIB
        )

    @log_and_handle_exceptions
    async def install_dsym(self, dsym: Bundle) -> InstalledArtifact:
        return await self._install_to_destination(
            bundle=dsym, destination=InstallRequest.DSYM
        )

    @log_and_handle_exceptions
    async def install_framework(self, framework_path: Bundle) -> InstalledArtifact:
        return await self._install_to_destination(
            bundle=framework_path, destination=InstallRequest.FRAMEWORK
        )

    async def _install_to_destination(
        self, bundle: Bundle, destination: Destination
    ) -> InstalledArtifact:
        async with self.get_stub() as stub, stub.install.open() as stream:
            generator = None
            if isinstance(bundle, str):
                url = urllib.parse.urlparse(bundle)
                if url.scheme:
                    # send url
                    payload = Payload(url=bundle)
                    generator = generate_requests([InstallRequest(payload=payload)])

                else:
                    file_path = str(Path(bundle).resolve(strict=True))
                    if none_throws(self.companion_info).is_local:
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
            response = await drain_to_stream(
                stream=stream, generator=generator, logger=self.logger
            )
            return InstalledArtifact(name=response.name, uuid=response.uuid)

    @log_and_handle_exceptions
    async def push(self, src_paths: List[str], bundle_id: str, dest_path: str) -> None:
        async with self.get_stub() as stub, stub.push.open() as stream:
            await stream.send_message(
                PushRequest(
                    inner=PushRequest.Inner(bundle_id=bundle_id, dst_path=dest_path)
                )
            )
            if none_throws(self.companion_info).is_local:
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
                        generate_tar(paths=src_paths),
                        lambda chunk: PushRequest(payload=Payload(data=chunk)),
                    ),
                    logger=self.logger,
                )

    @log_and_handle_exceptions
    async def pull(self, bundle_id: str, src_path: str, dest_path: str) -> None:
        async with self.get_stub() as stub, stub.pull.open() as stream:
            request = request = PullRequest(
                bundle_id=bundle_id,
                src_path=src_path,
                # not sending the destination to remote companion
                # so it streams the file back
                dst_path=dest_path
                if none_throws(self.companion_info).is_local
                else None,
            )
            await stream.send_message(request)
            await stream.end()
            if none_throws(self.companion_info).is_local:
                await stream.recv_message()
            else:
                await drain_untar(generate_bytes(stream), output_path=dest_path)
            self.logger.info(f"pulled file to {dest_path}")
        return PullResponse(payload=Payload(file_path=dest_path))

    @log_and_handle_exceptions
    async def list_test_bundle(self, test_bundle_id: str) -> List[str]:
        async with self.get_stub() as stub:
            response = await stub.xctest_list_tests(
                XctestListTestsRequest(bundle_name=test_bundle_id)
            )
            return [name for name in response.names]

    @log_and_handle_exceptions
    async def list_xctests(self) -> List[InstalledTestInfo]:
        async with self.get_stub() as stub:
            response = await stub.xctest_list_bundles(XctestListBundlesRequest())
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
    async def tap(self, x: int, y: int, duration: Optional[float] = None) -> None:
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
        delta: Optional[int] = None,
    ) -> None:
        await self.send_events(swipe_to_events(p_start, p_end, delta))

    @log_and_handle_exceptions
    async def key_sequence(self, key_sequence: List[int]) -> None:
        events: List[HIDEvent] = []
        for key in key_sequence:
            events.extend(key_press_to_events(key))
        await self.send_events(events)

    @log_and_handle_exceptions
    async def hid(self, event_iterator: AsyncIterable[HIDEvent]) -> None:
        async with self.get_stub() as stub, stub.hid.open() as stream:
            grpc_event_iterator = (
                event_to_grpc(event) async for event in event_iterator
            )
            await drain_to_stream(
                stream=stream, generator=grpc_event_iterator, logger=self.logger
            )
            await stream.recv_message()

    async def debug_server(self, request: DebugServerRequest) -> DebugServerResponse:
        async with self.get_stub() as stub, stub.debugserver.open() as stream:
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
        template: str,
        app_bundle_id: str,
        trace_path: str,
        post_process_arguments: Optional[List[str]] = None,
        env: Optional[Dict[str, str]] = None,
        app_args: Optional[List[str]] = None,
        started: Optional[asyncio.Event] = None,
        timings: Optional[InstrumentsTimings] = None,
    ) -> str:
        trace_path = os.path.realpath(trace_path)
        self.logger.info(f"Starting instruments connection, writing to {trace_path}")
        async with self.get_stub() as stub, stub.instruments_run.open() as stream:
            self.logger.info("Sending instruments request")
            await stream.send_message(
                InstrumentsRunRequest(
                    start=InstrumentsRunRequest.Start(
                        file_path=None,
                        template_name=template,
                        app_bundle_id=app_bundle_id,
                        environment=env,
                        arguments=app_args,
                        timings=translate_instruments_timings(timings),
                    )
                )
            )
            self.logger.info("Starting instruments")
            await drain_until_running(stream=stream, logger=self.logger)
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
            self.logger.info(f"Writing instruments from tar to {trace_path}")
            await drain_untar(
                instruments_generate_bytes(stream=stream, logger=self.logger),
                output_path=trace_path,
            )
            self.logger.info(f"Instruments trace written to {trace_path}")
            return trace_path

    @log_and_handle_exceptions
    async def launch(
        self,
        bundle_id: str,
        args: Optional[List[str]] = None,
        env: Optional[Dict[str, str]] = None,
        foreground_if_running: bool = False,
        stop: Optional[asyncio.Event] = None,
    ) -> None:
        async with self.get_stub() as stub, stub.launch.open() as stream:
            request = LaunchRequest(
                start=LaunchRequest.Start(
                    bundle_id=bundle_id,
                    env=env,
                    app_args=args,
                    foreground_if_running=foreground_if_running,
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
        self.logger.info(f"Starting connection to backend")
        async with self.get_stub() as stub, stub.record.open() as stream:
            if none_throws(self.companion_info).is_local:
                self.logger.info(
                    f"Starting video recording to local file {output_file}"
                )
                await stream.send_message(
                    RecordRequest(start=RecordRequest.Start(file_path=output_file))
                )
            else:
                self.logger.info(f"Starting video recording with response data")
                await stream.send_message(
                    RecordRequest(start=RecordRequest.Start(file_path=None))
                )
            await stop.wait()
            self.logger.info("Stopping video recording")
            await stream.send_message(RecordRequest(stop=RecordRequest.Stop()))
            await stream.end()
            if none_throws(self.companion_info).is_local:
                self.logger.info("Video saved at output path")
                await stream.recv_message()
            else:
                self.logger.info(f"Decompressing gzip to {output_file}")
                await drain_gzip_decompress(
                    generate_video_bytes(stream), output_path=output_file
                )
                self.logger.info(f"Finished decompression to {output_file}")

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
    ) -> AsyncIterator[TestRunInfo]:
        async with self.get_stub() as stub, stub.xctest_run.open() as stream:
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
            )
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
                    self.logger.info(line)
                    if idb_log_buffer:
                        idb_log_buffer.write(line)
                if result_bundle_path:
                    await write_result_bundle(
                        response=response,
                        output_path=result_bundle_path,
                        logger=self.logger,
                    )
                for result in make_results(response):
                    yield result

    async def _tail_specific_logs(
        self,
        source: LogRequest.Source,
        stop: asyncio.Event,
        arguments: Optional[List[str]],
    ) -> AsyncIterator[str]:
        async with self.get_stub() as stub, stub.log.open() as stream:
            await stream.send_message(
                LogRequest(arguments=arguments, source=source), end=True
            )
            async for message in cancel_wrapper(stream=stream, stop=stop):
                yield message.output.decode()

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
    async def boot(self) -> None:
        if self.target_udid:
            cmd: List[str] = ["idb_companion", "--boot", none_throws(self.target_udid)]
            process = await asyncio.create_subprocess_exec(
                *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            await process.communicate()
        else:
            raise IdbException("boot needs --udid to work")

    async def _companion_to_target(self, companion: CompanionInfo) -> TargetDescription:
        channel = Channel(companion.host, companion.port, loop=asyncio.get_event_loop())
        stub = CompanionServiceStub(channel=channel)
        response = await stub.describe(TargetDescriptionRequest())
        channel.close()
        return target_to_py(response.target_description)

    @log_and_handle_exceptions
    async def list_targets(self) -> List[TargetDescription]:
        await self.spawn_notifier()
        companions = self.direct_companion_manager.get_companions()
        local_targets = self.local_targets_manager.get_local_targets()
        connected_targets = await asyncio.gather(
            *(
                self._companion_to_target(companion=companion)
                for companion in companions
            )
        )
        return local_targets + list(connected_targets)

    @log_and_handle_exceptions
    async def connect(
        self,
        destination: ConnectionDestination,
        metadata: Optional[Dict[str, str]] = None,
    ) -> CompanionInfo:
        self.logger.debug(f"Connecting directly to {destination} with meta {metadata}")
        if isinstance(destination, Address):
            channel = Channel(
                destination.host, destination.port, loop=asyncio.get_event_loop()
            )
            stub = CompanionServiceStub(channel=channel)
            response = await stub.connect(
                ConnectRequest(
                    destination=destination_to_grpc(destination), metadata=metadata
                )
            )
            companion = CompanionInfo(
                udid=response.companion.udid,
                host=destination.host,
                port=destination.port,
                is_local=response.companion.is_local,
            )
            self.logger.debug(f"Connected directly to {companion}")
            self.direct_companion_manager.add_companion(companion)
            channel.close()
            return companion
        else:
            companion = await self.spawn_companion(target_udid=destination)
            if companion:
                return companion
            else:
                raise IdbException(f"can't find target for udid {destination}")

    @log_and_handle_exceptions
    async def disconnect(self, destination: ConnectionDestination) -> None:
        self.direct_companion_manager.remove_companion(destination)
