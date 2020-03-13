#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
from logging import Logger
from typing import IO, AsyncIterator, List, Union

import aiofiles
import idb.common.gzip as gzip
import idb.common.tar as tar
from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.grpc.idb_pb2 import InstallRequest, Payload
from idb.grpc.xctest import xctest_paths_to_tar


CHUNK_SIZE = 16384
Destination = InstallRequest.Destination
Bundle = Union[str, IO[bytes]]


async def _generate_ipa_chunks(
    ipa_path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating Chunks for .ipa {ipa_path}")
    async with aiofiles.open(ipa_path, "r+b") as file:
        while True:
            chunk = await file.read(CHUNK_SIZE)
            if not chunk:
                logger.debug(f"Finished generating .ipa chunks for {ipa_path}")
                return
            yield InstallRequest(payload=Payload(data=chunk))


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


async def _generate_dsym_chunks(
    path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    async for chunk in tar.generate_tar([path]):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating chunks {path}")


async def _generate_framework_chunks(
    path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    async for chunk in tar.generate_tar([path]):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating chunks {path}")


async def generate_requests(
    requests: List[InstallRequest]
) -> AsyncIterator[InstallRequest]:
    for request in requests:
        yield request


async def generate_io_chunks(
    io: IO[bytes], logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug("Generating io chunks")
    while True:
        chunk = io.read(CHUNK_SIZE)
        if not chunk:
            logger.debug(f"Finished generating byte chunks")
            return
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug("Finished generating io chunks")


def generate_binary_chunks(
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
    elif destination == InstallRequest.DSYM:
        return _generate_dsym_chunks(path=path, logger=logger)
    elif destination == InstallRequest.FRAMEWORK:
        return _generate_framework_chunks(path=path, logger=logger)
    raise GRPCError(
        status=Status(Status.FAILED_PRECONDITION),
        message=f"install invalid for {path} {destination}",
    )
