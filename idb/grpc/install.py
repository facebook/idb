#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import os
import struct
from collections.abc import AsyncIterator
from logging import Logger
from typing import IO, List, Optional, Union

import aiofiles
import idb.common.gzip as gzip
import idb.common.tar as tar
from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.common.types import Compression
from idb.grpc.idb_pb2 import InstallRequest, Payload
from idb.grpc.xctest import xctest_paths_to_tar


CHUNK_SIZE = (
    1024 * 1024 * 4
)  # 4Mb, matching tar.py/gzip.py and well under the companion's 16Mb max receive size
Destination = InstallRequest.Destination
Bundle = Union[str, IO[bytes]]
ZIP_SIGNATURE = b"PK\x03\x04"
# A zstd skippable frame that tells a companion advertising `zstd_zip_streams`
# that the zstd stream after it decompresses to a zip, rather than to a tar.
ZSTD_ZIP_STREAM_MARKER: bytes = struct.pack("<II", 0x184D2A5E, 8) + b"idb-zip\0"


ZIP_DATA_DESCRIPTOR_SIGNATURE = b"PK\x07\x08"
ZIP_STORED = 0
ZIP_HAS_DATA_DESCRIPTOR = 0x08


def _zip_stores_files(head: bytes) -> bool:
    """Whether the first file in a zip is stored rather than compressed.

    Directory entries are skipped since zip tools store them even in a
    deflated archive. Returns True when `head` ends before the first file.
    """
    offset = 0
    while head.startswith(ZIP_SIGNATURE, offset) and len(head) >= offset + 30:
        (flags, method) = struct.unpack_from("<HH", head, offset + 6)
        (compressed_size,) = struct.unpack_from("<I", head, offset + 18)
        (name_length, extra_length) = struct.unpack_from("<HH", head, offset + 26)
        name_end = offset + 30 + name_length
        if not head[offset + 30 : name_end].endswith(b"/"):
            return method == ZIP_STORED
        offset = name_end + extra_length + compressed_size
        if flags & ZIP_HAS_DATA_DESCRIPTOR:
            if head.startswith(ZIP_DATA_DESCRIPTOR_SIGNATURE, offset):
                offset += 4
            offset += 12
    return True


async def _read_file(path: str) -> AsyncIterator[bytes]:
    async with aiofiles.open(path, "rb") as file:
        while chunk := await file.read(CHUNK_SIZE):
            yield chunk


async def _read_io(io: IO[bytes]) -> AsyncIterator[bytes]:
    while chunk := io.read(CHUNK_SIZE):
        yield chunk


async def _prepend(first: bytes, rest: AsyncIterator[bytes]) -> AsyncIterator[bytes]:
    if first:
        yield first
    async for chunk in rest:
        yield chunk


async def _zstd_zip_stream(zip_chunks: AsyncIterator[bytes]) -> AsyncIterator[bytes]:
    yield ZSTD_ZIP_STREAM_MARKER
    async for chunk in tar.compress_zstd(zip_chunks):
        yield chunk


async def _generate_payloads(
    chunks: AsyncIterator[bytes], zstd_zip_stream: bool, logger: Logger
) -> AsyncIterator[InstallRequest]:
    first = await anext(chunks, b"")
    stream = _prepend(first, chunks)
    if zstd_zip_stream and first.startswith(ZIP_SIGNATURE):
        if _zip_stores_files(first):
            logger.debug("Streaming zip with ZSTD compression")
            stream = _zstd_zip_stream(stream)
        else:
            logger.debug("Streaming zip as is, its files are already compressed")
    async for chunk in stream:
        yield InstallRequest(payload=Payload(data=chunk))


async def _generate_ipa_chunks(
    ipa_path: str, zstd_zip_stream: bool, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating Chunks for .ipa {ipa_path}")
    async for request in _generate_payloads(
        _read_file(ipa_path), zstd_zip_stream=zstd_zip_stream, logger=logger
    ):
        yield request
    logger.debug(f"Finished generating .ipa chunks for {ipa_path}")


async def _generate_app_chunks(
    app_path: str, compression: Compression, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for .app {app_path}")
    async for chunk in tar.generate_tar(paths=[app_path], compression=compression):
        yield InstallRequest(payload=Payload(data=chunk))
    logger.debug(f"Finished generating .app chunks {app_path}")


async def _generate_xctest_chunks(
    path: str, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    async for chunk in tar.generate_tar(xctest_paths_to_tar(path, logger)):
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
    path: str, compression: Compression, logger: Logger
) -> AsyncIterator[InstallRequest]:
    logger.debug(f"Generating chunks for {path}")
    async for chunk in tar.generate_tar([path], compression):
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
    requests: list[InstallRequest],
) -> AsyncIterator[InstallRequest]:
    for request in requests:
        yield request


async def generate_io_chunks(
    io: IO[bytes], logger: Logger, zstd_zip_stream: bool = False
) -> AsyncIterator[InstallRequest]:
    logger.debug("Generating io chunks")
    async for request in _generate_payloads(
        _read_io(io), zstd_zip_stream=zstd_zip_stream, logger=logger
    ):
        yield request
    logger.debug("Finished generating io chunks")


def select_stream_compression(
    requested: Compression | None, supported: frozenset[Compression]
) -> Compression | None:
    # Without zstd, leave the compression unset so the request carries no compression frame and the
    # companion applies its gzip default, as it did before companions advertised compressions.
    if (
        requested is None
        and Compression.ZSTD in supported
        and tar.has_zstd_compressor()
    ):
        return Compression.ZSTD
    return requested


def generate_binary_chunks(
    path: str,
    destination: Destination,
    compression: Compression | None,
    logger: Logger,
    zstd_zip_stream: bool = False,
) -> AsyncIterator[InstallRequest]:
    if destination == InstallRequest.APP:
        if path.endswith(".ipa"):
            return _generate_ipa_chunks(
                ipa_path=path, zstd_zip_stream=zstd_zip_stream, logger=logger
            )
        elif path.endswith(".app"):
            return _generate_app_chunks(
                app_path=path,
                compression=compression or Compression.GZIP,
                logger=logger,
            )
    elif destination == InstallRequest.XCTEST:
        return _generate_xctest_chunks(path=path, logger=logger)
    elif destination == InstallRequest.DYLIB:
        return _generate_dylib_chunks(path=path, logger=logger)
    elif destination == InstallRequest.DSYM:
        return _generate_dsym_chunks(
            path=path, compression=compression or Compression.GZIP, logger=logger
        )
    elif destination == InstallRequest.FRAMEWORK:
        return _generate_framework_chunks(path=path, logger=logger)
    raise GRPCError(
        status=Status(Status.FAILED_PRECONDITION),
        message=f"install invalid for {path} {destination}",
    )
