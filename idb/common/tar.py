#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import os
import sys
import tempfile
import uuid
from typing import AsyncContextManager, AsyncIterator, List, Optional

from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


class TarException(BaseException):
    pass


def _has_executable(exe: str) -> bool:
    return any((os.path.exists(os.path.join(path, exe)) for path in os.get_exec_path()))


COMPRESSION_COMMAND = "pigz -c" if _has_executable("pigz") else "gzip -4"
READ_CHUNK_SIZE: int = 1024 * 1024 * 4  # 4Mb, the default max read for gRPC


@asynccontextmanager  # noqa T484
async def _create_tar_command(
    paths: List[str],
    additional_tar_args: Optional[List[str]],
    place_in_subfolders: bool,
) -> AsyncContextManager[asyncio.subprocess.Process]:
    with tempfile.TemporaryDirectory(prefix="tar_link_") as temp_dir:
        tar_args = additional_tar_args or []
        if place_in_subfolders:
            for path in paths:
                sub_dir_name = str(uuid.uuid4())
                temp_subdir = os.path.join(temp_dir, sub_dir_name)
                os.symlink(os.path.dirname(path), temp_subdir)
                path_to_file = os.path.join(sub_dir_name, os.path.basename(path))
                tar_args.append(f"-C {temp_dir} {path_to_file}")
        else:
            tar_args.extend(
                [
                    f"-C {os.path.dirname(path)} {os.path.basename(path)}"
                    for path in paths
                ]
            )
        process = await asyncio.create_subprocess_shell(
            f'tar cfv - {" ".join(tar_args)} | {COMPRESSION_COMMAND}',
            stderr=sys.stderr,
            stdout=asyncio.subprocess.PIPE,
        )
        yield process


@asynccontextmanager  # noqa T484
async def _create_untar_command(
    output_path: str,
) -> AsyncContextManager[asyncio.subprocess.Process]:
    process = await asyncio.create_subprocess_shell(
        f"tar -C {output_path} -vxzpf -",
        stdin=asyncio.subprocess.PIPE,
        stderr=sys.stderr,
        stdout=sys.stderr,
    )
    yield process


async def _generator_from_data(data: bytes) -> AsyncIterator[bytes]:
    yield data


async def create_tar(
    paths: List[str],
    additional_tar_args: Optional[List[str]] = None,
    place_in_subfolders: bool = False,
) -> bytes:
    async with _create_tar_command(
        paths=paths,
        additional_tar_args=additional_tar_args,
        place_in_subfolders=place_in_subfolders,
    ) as process:
        tar_contents = (await process.communicate())[0]
        if process.returncode != 0:
            raise TarException(
                "Failed to create tar file, "
                "tar command exited with non-zero exit code {process.returncode}"
            )
        return tar_contents


async def generate_tar(
    paths: List[str],
    additional_tar_args: Optional[List[str]] = None,
    place_in_subfolders: bool = False,
) -> AsyncIterator[bytes]:
    async with _create_tar_command(
        paths=paths,
        additional_tar_args=additional_tar_args,
        place_in_subfolders=place_in_subfolders,
    ) as process:
        reader = none_throws(process.stdout)
        while not reader.at_eof():
            data = await reader.read(READ_CHUNK_SIZE)
            if not data:
                break
            yield data
        returncode = await process.wait()
        if returncode != 0:
            raise TarException(
                "Failed to generate tar file, tar command exited with non-zero exit code {returncode}"
            )


async def drain_untar(generator: AsyncIterator[bytes], output_path: str) -> None:
    try:
        os.mkdir(output_path)
    except FileExistsError:
        pass
    async with _create_untar_command(output_path=output_path) as process:
        writer = none_throws(process.stdin)
        async for data in generator:
            writer.write(data)
            await writer.drain()
        writer.write_eof()
        await writer.drain()
        await process.wait()


async def untar(data: bytes, output_path: str) -> None:
    await drain_untar(
        generator=_generator_from_data(data=data), output_path=output_path
    )
