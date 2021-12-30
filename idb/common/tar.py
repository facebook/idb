#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import os
import sys
import tempfile
import uuid
from abc import abstractmethod
from typing import AsyncGenerator, AsyncIterator, List, Optional

from idb.common.types import Compression
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


class TarException(BaseException):
    pass


def _has_executable(exe: str) -> bool:
    return any((os.path.exists(os.path.join(path, exe)) for path in os.get_exec_path()))


READ_CHUNK_SIZE: int = 1024 * 1024 * 4  # 4Mb, the default max read for gRPC


async def is_gnu_tar() -> bool:
    proc = await asyncio.create_subprocess_shell(
        "tar --version | grep GNU",
        stdout=asyncio.subprocess.DEVNULL,
        stderr=asyncio.subprocess.DEVNULL,
    )
    await proc.communicate()
    return proc.returncode == 0


class TarArchiveProcess:
    def __init__(
        self,
        paths: List[str],
        additional_tar_args: Optional[List[str]],
        place_in_subfolders: bool,
        verbose: bool,
    ) -> None:
        self._paths = paths
        self._additional_tar_args = additional_tar_args
        self._place_in_subfolders = place_in_subfolders
        self._verbose = verbose

    @asynccontextmanager
    async def run(self) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        with tempfile.TemporaryDirectory(prefix="tar_link_") as temp_dir:
            command = self._tar_command
            self._apply_additional_args(command, temp_dir)
            async with self._run_process(command) as process:
                yield process

    def _apply_additional_args(self, command: List[str], temp_dir: str) -> None:
        additional_args = self._additional_tar_args
        if additional_args:
            command.extend(additional_args)

        if self._place_in_subfolders:
            for path in self._paths:
                sub_dir_name = str(uuid.uuid4())
                temp_subdir = os.path.join(temp_dir, sub_dir_name)
                os.symlink(os.path.dirname(path), temp_subdir)
                path_to_file = os.path.join(sub_dir_name, os.path.basename(path))
                command.extend(["-C", temp_dir, path_to_file])
        else:
            for path in self._paths:
                command.extend(["-C", os.path.dirname(path), os.path.basename(path)])

    @property
    @abstractmethod
    def _tar_command(self) -> List[str]:
        pass

    @asynccontextmanager
    @abstractmethod
    def _run_process(
        self, command: List[str]
    ) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        pass


class GzipArchive(TarArchiveProcess):
    GZIP_COMPRESSION_COMMAND = (
        ["pigz", "-c"] if _has_executable("pigz") else ["gzip", "-4"]
    )

    @property
    def _tar_command(self) -> List[str]:
        return ["tar", "vcf" if self._verbose else "cf", "-"]

    @asynccontextmanager
    async def _run_process(
        self, command: List[str]
    ) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        pipe_read, pipe_write = os.pipe()
        process_tar = await asyncio.create_subprocess_exec(
            *command, stderr=sys.stderr, stdout=pipe_write
        )
        os.close(pipe_write)
        process_compressor = await asyncio.create_subprocess_exec(
            *self.GZIP_COMPRESSION_COMMAND,
            stdin=pipe_read,
            stderr=sys.stderr,
            stdout=asyncio.subprocess.PIPE,
        )
        os.close(pipe_read)
        yield process_compressor
        await asyncio.gather(process_tar.wait(), process_compressor.wait())


class ZstdArchive(TarArchiveProcess):
    ZSTD_EXECUTABLES: List[str] = ["pzstd", "zstd"]  # in the order of preference

    @property
    def _tar_command(self) -> List[str]:
        return [
            "tar",
            "--use-compress-program",
            self._get_zstd_exe(),
            "-vcf" if self._verbose else "-cf",
            "-",
        ]

    @asynccontextmanager
    async def _run_process(
        self, command: List[str]
    ) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        process = await asyncio.create_subprocess_exec(
            *command, stderr=sys.stderr, stdout=asyncio.subprocess.PIPE
        )
        yield process
        await process.wait()

    @classmethod
    def _get_zstd_exe(cls) -> str:
        for zstd_exe in cls.ZSTD_EXECUTABLES:
            if _has_executable(zstd_exe):
                return zstd_exe
        raise Exception(
            f"Missing ZSTD dependencies. Make sure either of {cls.ZSTD_EXECUTABLES} is on the PATH"
        )


def _create_untar_command(
    output_path: str, gnu_tar: bool, verbose: bool = False
) -> List[str]:
    command = ["tar", "-C", output_path]
    if not verbose and gnu_tar:
        command.append("--warning=no-unknown-keyword")
    command.append(f"-xzpf{'v' if verbose else ''}")
    command.append("-")
    return command


async def _generator_from_data(data: bytes) -> AsyncIterator[bytes]:
    yield data


async def create_tar(
    paths: List[str],
    additional_tar_args: Optional[List[str]] = None,
    place_in_subfolders: bool = False,
    verbose: bool = False,
) -> bytes:
    async with GzipArchive(
        paths=paths,
        additional_tar_args=additional_tar_args,
        place_in_subfolders=place_in_subfolders,
        verbose=verbose,
    ).run() as process:
        tar_contents = (await process.communicate())[0]
        if process.returncode != 0:
            raise TarException(
                "Failed to create tar file, "
                "tar command exited with non-zero exit code {process.returncode}"
            )
        return tar_contents


async def generate_tar(
    paths: List[str],
    compression: Compression = Compression.GZIP,
    additional_tar_args: Optional[List[str]] = None,
    place_in_subfolders: bool = False,
    verbose: bool = False,
) -> AsyncIterator[bytes]:
    if compression == Compression.ZSTD:
        tar_process: TarArchiveProcess = ZstdArchive(
            paths=paths,
            additional_tar_args=additional_tar_args,
            place_in_subfolders=place_in_subfolders,
            verbose=verbose,
        )
    elif compression == Compression.GZIP:
        tar_process = GzipArchive(
            paths=paths,
            additional_tar_args=additional_tar_args,
            place_in_subfolders=place_in_subfolders,
            verbose=verbose,
        )
    else:
        raise Exception(f"Unsupported compression format: {compression}")

    async with tar_process.run() as process:
        reader = none_throws(process.stdout)
        while not reader.at_eof():
            data = await reader.read(READ_CHUNK_SIZE)
            if not data:
                break
            yield data
        returncode = await process.wait()
        if returncode != 0:
            raise TarException(
                "Failed to generate tar file, "
                f"tar command exited with non-zero exit code {returncode}"
            )


async def drain_untar(
    generator: AsyncIterator[bytes], output_path: str, verbose: bool = False
) -> None:
    try:
        os.mkdir(output_path)
    except FileExistsError:
        pass

    process = await asyncio.create_subprocess_exec(
        *_create_untar_command(
            output_path=output_path, gnu_tar=await is_gnu_tar(), verbose=verbose
        ),
        stdin=asyncio.subprocess.PIPE,
        stderr=sys.stderr,
        stdout=sys.stderr,
    )
    writer = none_throws(process.stdin)
    async for data in generator:
        writer.write(data)
        await writer.drain()
    writer.write_eof()
    await writer.drain()
    await process.wait()


async def untar(data: bytes, output_path: str, verbose: bool = False) -> None:
    await drain_untar(
        generator=_generator_from_data(data=data),
        output_path=output_path,
        verbose=verbose,
    )
