#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import asyncio
import contextlib
import os
import sys
import tempfile
import uuid
from abc import abstractmethod
from collections.abc import AsyncGenerator, AsyncIterator
from typing import List, Optional

from idb.common.types import Compression
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


class TarException(BaseException):
    pass


def _has_executable(exe: str) -> bool:
    return any(os.path.exists(os.path.join(path, exe)) for path in os.get_exec_path())


READ_CHUNK_SIZE: int = 1024 * 1024 * 4  # 4Mb, the default max read for gRPC


def _tar_environment() -> dict[str, str]:
    # Otherwise macOS tar adds an AppleDouble entry for every file's extended attributes, which
    # takes several times longer than archiving the files themselves, and bundles don't need them.
    return {**os.environ, "COPYFILE_DISABLE": "1"}


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
        paths: list[str],
        additional_tar_args: list[str] | None,
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

    def _apply_additional_args(self, command: list[str], temp_dir: str) -> None:
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
    def _tar_command(self) -> list[str]:
        return ["tar", "vcf" if self._verbose else "cf", "-"]

    @property
    @abstractmethod
    def _compress_command(self) -> list[str]:
        pass

    # tar's own compress-program support is not used: bsdtar pads the compressed output to its
    # block size with zeros, which zstd rejects as a malformed frame.
    @asynccontextmanager
    async def _run_process(
        self, command: list[str]
    ) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        compress_command = self._compress_command
        pipe_read, pipe_write = os.pipe()
        try:
            process_tar = await asyncio.create_subprocess_exec(
                *command, stderr=sys.stderr, stdout=pipe_write, env=_tar_environment()
            )
        except BaseException:
            os.close(pipe_read)
            raise
        finally:
            os.close(pipe_write)
        try:
            process_compressor = await asyncio.create_subprocess_exec(
                *compress_command,
                stdin=pipe_read,
                stderr=sys.stderr,
                stdout=asyncio.subprocess.PIPE,
            )
        except BaseException:
            with contextlib.suppress(ProcessLookupError):
                process_tar.kill()
            await process_tar.wait()
            raise
        finally:
            os.close(pipe_read)
        processes = (process_tar, process_compressor)
        try:
            yield process_compressor
        except BaseException:
            # A caller that stops reading leaves both blocked on full pipes.
            for process in processes:
                with contextlib.suppress(ProcessLookupError):
                    process.kill()
            raise
        finally:
            await asyncio.gather(*(process.wait() for process in processes))
        # The compressor exits cleanly on whatever tar managed to write.
        if process_tar.returncode != 0:
            raise TarException(
                f"Failed to create tar file, tar exited with {process_tar.returncode}"
            )


class GzipArchive(TarArchiveProcess):
    GZIP_COMPRESSION_COMMAND = (
        ["pigz", "-c"] if _has_executable("pigz") else ["gzip", "-4"]
    )

    @property
    def _compress_command(self) -> list[str]:
        return self.GZIP_COMPRESSION_COMMAND


class ZstdArchive(TarArchiveProcess):
    ZSTD_EXECUTABLES: list[str] = ["pzstd", "zstd"]  # in the order of preference

    @property
    def _compress_command(self) -> list[str]:
        return [self._get_zstd_exe(), "-c"]

    @classmethod
    def _find_zstd_exe(cls) -> str | None:
        return next((exe for exe in cls.ZSTD_EXECUTABLES if _has_executable(exe)), None)

    @classmethod
    def _get_zstd_exe(cls) -> str:
        zstd_exe = cls._find_zstd_exe()
        if zstd_exe is None:
            raise Exception(
                f"Missing ZSTD dependencies. Make sure either of {cls.ZSTD_EXECUTABLES} is on the PATH"
            )
        return zstd_exe


def has_zstd_compressor() -> bool:
    return ZstdArchive._find_zstd_exe() is not None


async def compress_zstd(chunks: AsyncIterator[bytes]) -> AsyncIterator[bytes]:
    process = await asyncio.create_subprocess_exec(
        ZstdArchive._get_zstd_exe(),
        "-q",
        "-c",
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=sys.stderr,
    )
    writer = none_throws(process.stdin)
    reader = none_throws(process.stdout)

    async def feed() -> None:
        try:
            async for chunk in chunks:
                writer.write(chunk)
                await writer.drain()
        finally:
            writer.close()

    feeding = asyncio.create_task(feed())
    try:
        while data := await reader.read(READ_CHUNK_SIZE):
            yield data
        await feeding
    except BaseException:
        feeding.cancel()
        with contextlib.suppress(ProcessLookupError):
            process.kill()
        raise
    finally:
        returncode = await process.wait()
    if returncode != 0:
        raise TarException(f"zstd exited with non-zero exit code {returncode}")


def _create_untar_command(
    output_path: str, gnu_tar: bool, verbose: bool = False
) -> list[str]:
    command = ["tar", "-C", output_path]
    if not verbose and gnu_tar:
        command.append("--warning=no-unknown-keyword")
    command.append(f"-xzpf{'v' if verbose else ''}")
    command.append("-")
    return command


async def _generator_from_data(data: bytes) -> AsyncIterator[bytes]:
    yield data


async def create_tar(
    paths: list[str],
    additional_tar_args: list[str] | None = None,
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
                f"tar command exited with non-zero exit code {process.returncode}"
            )
        return tar_contents


async def generate_tar(
    paths: list[str],
    compression: Compression = Compression.GZIP,
    additional_tar_args: list[str] | None = None,
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
