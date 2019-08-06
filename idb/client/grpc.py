#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import logging
import urllib.parse
import warnings
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import idb.grpc.ipc_loader as ipc_loader
from grpclib.client import Channel
from grpclib.exceptions import GRPCError, ProtocolError, StreamTerminatedError
from idb.client.daemon_pid_saver import kill_saved_pids
from idb.client.daemon_spawner import DaemonSpawner
from idb.common.direct_companion_manager import DirectCompanionManager
from idb.common.install import (
    Bundle,
    Destination,
    generate_binary_chunks,
    generate_io_chunks,
    generate_requests,
)
from idb.common.logging import log_call
from idb.common.stream import stream_map
from idb.common.tar import create_tar, generate_tar
from idb.common.types import (
    AccessibilityInfo,
    AppProcessState,
    CompanionInfo,
    CrashLog,
    CrashLogInfo,
    CrashLogQuery,
    FileEntryInfo,
    IdbClient,
    IdbException,
    InstalledAppInfo,
    InstalledArtifact,
    TargetDescription,
)
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import (
    AccessibilityInfoRequest,
    AddMediaRequest,
    ApproveRequest,
    ClearKeychainRequest,
    ContactsUpdateRequest,
    CrashShowRequest,
    FocusRequest,
    InstallRequest,
    ListAppsRequest,
    Location,
    LsRequest,
    MkdirRequest,
    MvRequest,
    OpenUrlRequest,
    Payload,
    Point,
    PushRequest,
    PushResponse,
    RmRequest,
    ScreenshotRequest,
    SetLocationRequest,
    TargetDescriptionRequest,
    TerminateRequest,
    UninstallRequest,
)
from idb.grpc.stream import drain_to_stream
from idb.grpc.types import CompanionClient
from idb.ipc.mapping.crash import (
    _to_crash_log,
    _to_crash_log_info_list,
    _to_crash_log_query_proto,
)
from idb.ipc.mapping.target import target_to_py


APPROVE_MAP: Dict[str, Any] = {
    "photos": ApproveRequest.PHOTOS,
    "camera": ApproveRequest.CAMERA,
    "contacts": ApproveRequest.CONTACTS,
}

# this is to silence the channel not closed warning
# https://github.com/vmagamedov/grpclib/issues/58
warnings.filterwarnings(action="ignore", category=ResourceWarning)


def log_and_handle_exceptions(func):  # pyre-ignore
    @log_call(name=func.__name__)
    def func_wrapper(*args, **kwargs):  # pyre-ignore

        try:
            return func(*args, **kwargs)

        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    return func_wrapper


class GrpcClient(IdbClient):
    def __init__(
        self,
        port: int,
        host: str,
        target_udid: Optional[str],
        logger: Optional[logging.Logger] = None,
        force_kill_daemon: bool = False,
    ) -> None:
        self.port: int = port
        self.host: str = host
        self.logger: logging.Logger = (
            logger if logger else logging.getLogger("idb_grpc_client")
        )
        self.force_kill_daemon = force_kill_daemon
        self.target_udid = target_udid
        self.daemon_spawner = DaemonSpawner(host=self.host, port=self.port)
        self.daemon_channel: Optional[Channel] = None
        self.daemon_stub: Optional[CompanionServiceStub] = None
        for (call_name, f) in ipc_loader.client_calls(
            daemon_provider=self.provide_client
        ):
            setattr(self, call_name, f)
        # this is temporary while we are killing the daemon
        # the cli needs access to the new direct_companion_manager to route direct
        # commands.
        # this overrides the stub to talk directly to the companion
        self.direct_companion_manager = DirectCompanionManager(logger=self.logger)
        self.channel: Optional[Channel] = None
        self.stub: Optional[CompanionServiceStub] = None
        try:
            self.companion_info: CompanionInfo = self.direct_companion_manager.get_companion_info(
                target_udid=self.target_udid
            )
            self.logger.info(f"using companion {self.companion_info}")
            self.channel = Channel(
                self.companion_info.host,
                self.companion_info.port,
                loop=asyncio.get_event_loop(),
            )
            self.stub: Optional[CompanionServiceStub] = CompanionServiceStub(
                channel=self.channel
            )
        except IdbException as e:
            self.logger.info(e)

    async def provide_client(self) -> CompanionClient:
        await self.daemon_spawner.start_daemon_if_needed(
            force_kill=self.force_kill_daemon
        )
        if not self.daemon_channel or not self.daemon_stub:
            self.daemon_channel = Channel(
                self.host, self.port, loop=asyncio.get_event_loop()
            )
            self.daemon_stub = CompanionServiceStub(channel=self.daemon_channel)
        return CompanionClient(
            stub=self.daemon_stub,
            is_local=True,
            udid=self.target_udid,
            logger=self.logger,
        )

    @property
    def metadata(self) -> Dict[str, str]:
        if self.target_udid:
            return {"udid": self.target_udid}
        else:
            return {}

    @log_and_handle_exceptions
    async def kill(self) -> None:
        await kill_saved_pids()
        self.direct_companion_manager.clear()

    @log_and_handle_exceptions
    async def list_apps(self) -> List[InstalledAppInfo]:
        response = await self.stub.list_apps(ListAppsRequest())
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
        grpc_point = Point(x=point[0], y=point[1]) if point is not None else None
        response = await self.stub.accessibility_info(
            AccessibilityInfoRequest(point=grpc_point)
        )
        return AccessibilityInfo(json=response.json)

    @log_and_handle_exceptions
    async def add_media(self, file_paths: List[str]) -> None:
        async with self.stub.add_media.open() as stream:
            if self.companion_info.is_local:
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
        await self.stub.approve(
            ApproveRequest(
                bundle_id=bundle_id,
                permissions=[APPROVE_MAP[permission] for permission in permissions],
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
    async def describe(self) -> TargetDescription:
        response = await self.stub.describe(TargetDescriptionRequest())
        return target_to_py(response.target_description)

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
    async def rm(self, bundle_id: str, paths: List[str]) -> None:
        await self.stub.rm(RmRequest(bundle_id=bundle_id, paths=paths))

    @log_and_handle_exceptions
    async def mv(self, bundle_id: str, src_paths: List[str], dest_path: str) -> None:
        await self.stub.mv(
            MvRequest(bundle_id=bundle_id, src_paths=src_paths, dst_path=dest_path)
        )

    @log_and_handle_exceptions
    async def ls(self, bundle_id: str, path: str) -> List[FileEntryInfo]:
        response = await self.stub.ls(LsRequest(bundle_id=bundle_id, path=path))
        return [FileEntryInfo(path=file.path) for file in response.files]

    @log_and_handle_exceptions
    async def mkdir(self, bundle_id: str, path: str) -> None:
        await self.stub.mkdir(MkdirRequest(bundle_id=bundle_id, path=path))

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
        generator = None
        if isinstance(bundle, str):
            url = urllib.parse.urlparse(bundle)
            if url.scheme:
                # send url
                payload = Payload(url=bundle)
                async with self.stub.install.open() as stream:
                    generator = generate_requests([InstallRequest(payload=payload)])

            else:
                file_path = str(Path(bundle).resolve(strict=True))
                if self.companion_info.is_local:
                    # send file_path
                    async with self.stub.install.open() as stream:
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
        async with self.stub.install.open() as stream:
            await stream.send_message(InstallRequest(destination=destination))
            response = await drain_to_stream(
                stream=stream, generator=generator, logger=self.logger
            )
            return InstalledArtifact(name=response.name, uuid=response.uuid)

    @log_and_handle_exceptions
    async def push(self, src_paths: List[str], bundle_id: str, dest_path: str) -> None:
        async with self.stub.push.open() as stream:
            await stream.send_message(
                PushRequest(
                    inner=PushRequest.Inner(bundle_id=bundle_id, dst_path=dest_path)
                )
            )
            if self.companion_info.is_local:
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
