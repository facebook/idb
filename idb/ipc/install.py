#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import os
from logging import Logger
from pathlib import Path
from typing import AsyncIterator

import aiofiles
import idb.common.gzip as gzip
import idb.common.tar as tar
from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.grpc.types import CompanionClient
from idb.grpc.stream import Stream, drain_to_stream
from idb.common.xctest import xctest_paths_to_tar
from idb.grpc.idb_pb2 import InstallRequest, InstallResponse, Payload
from idb.utils.typing import none_throws


Destination = InstallRequest.Destination


async def _generate_ipa_chunks(
    ipa_path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating Chunks for .ipa {ipa_path}")
    async with aiofiles.open(ipa_path, "r+b") as file:
        while True:
            chunk = await file.read(1024)
            yield InstallRequest(payload=Payload(data=chunk))
            if not chunk:
                logger.debug(f"Finished generating .ipa chunks for {ipa_path}")
                return


async def _generate_app_chunks(
    app_path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for .app {app_path}")
    async for chunk in tar.generate_tar([app_path]):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating .app chunks {app_path}")


async def _generate_xctest_chunks(
    path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    async for chunk in tar.generate_tar(xctest_paths_to_tar(path)):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating chunks {path}")


async def _generate_dylib_chunks(
    path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    yield InstallRequest(name_hint=os.path.basename(path))
    async for chunk in gzip.generate_gzip(path):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating chunks {path}")


def _generate_binary_chunks(
    path: str, destination: Destination, logger: Logger
) -> AsyncIterator[InstallRequest]:
    if destination == InstallRequest.APP:
        if path.endswith(".ipa"):
            return _generate_ipa_chunks(ipa_path=path, logger=logger)
        elif path.endswith(".app"):
            return _generate_app_chunks(app_path=path, logger=logger)
    elif destination == InstallRequest.XCTEST:
        return _generate_xctest_chunks(path=path, logger=logger)
    elif destination == InstallRequest.DYLIB:
        return _generate_dylib_chunks(path=path, logger=logger)
    raise GRPCError(
        status=Status(Status.FAILED_PRECONDITION),
        message=f"install invalid for {path} {destination}",
    )


async def _install_to_destination(
    client: CompanionClient, path: str, destination: Destination
) -> str:
    abs_path = str(Path(path).resolve(strict=True))
    async with client.stub.install.open() as stream:
        await stream.send_message(InstallRequest(destination=destination))
        await stream.send_message(InstallRequest(payload=Payload(file_path=abs_path)))
        await stream.end()
        response = await stream.recv_message()
        return response.bundle_id


async def install(client: CompanionClient, bundle_path: str) -> str:
    return await _install_to_destination(
        client=client, path=bundle_path, destination=InstallRequest.APP
    )


async def install_xctest(client: CompanionClient, bundle_path: str) -> str:
    return await _install_to_destination(
        client=client, path=bundle_path, destination=InstallRequest.XCTEST
    )


async def install_dylib(client: CompanionClient, dylib_path: str) -> str:
    return await _install_to_destination(
        client=client, path=dylib_path, destination=InstallRequest.DYLIB
    )


async def daemon(
    client: CompanionClient, stream: Stream[InstallResponse, InstallRequest]
) -> None:
    destination_message = none_throws(await stream.recv_message())
    payload_message = none_throws(await stream.recv_message())
    file_path = payload_message.payload.file_path
    destination = destination_message.destination
    async with client.stub.install.open() as forward_stream:
        await forward_stream.send_message(destination_message)
        if client.is_local:
            await forward_stream.send_message(payload_message)
            await forward_stream.end()
            response = none_throws(await forward_stream.recv_message())
        else:
            response = await drain_to_stream(
                stream=forward_stream,
                generator=_generate_binary_chunks(
                    path=file_path, destination=destination, logger=client.logger
                ),
                logger=client.logger,
            )
        await stream.send_message(response, end=True)


CLIENT_PROPERTIES = [install, install_xctest, install_dylib]  # pyre-ignore
