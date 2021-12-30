#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import json
import logging
import os
import subprocess
from dataclasses import dataclass
from datetime import timedelta
from logging import Logger, DEBUG as LOG_LEVEL_DEBUG
from typing import AsyncGenerator, Dict, List, Optional, Sequence, Union, Tuple

from idb.common.constants import IDB_LOGS_PATH
from idb.common.file import get_last_n_lines
from idb.common.format import (
    target_description_from_json,
    target_descriptions_from_json,
)
from idb.common.logging import log_call
from idb.common.types import (
    Companion as CompanionBase,
    ECIDFilter,
    IdbException,
    OnlyFilter,
    TargetDescription,
    TargetType,
)
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


DEFAULT_ERASE_COMMAND_TIMEOUT = timedelta(minutes=3)
DEFAULT_COMPANION_COMMAND_TIMEOUT = timedelta(seconds=120)
DEFAULT_COMPANION_TEARDOWN_TIMEOUT = timedelta(seconds=30)


class IdbJsonException(Exception):
    pass


class CompanionSpawnerException(Exception):
    pass


async def _terminate_process(
    process: asyncio.subprocess.Process, timeout: timedelta, logger: logging.Logger
) -> None:
    returncode = process.returncode
    if returncode is not None:
        logger.info(f"Process has exited with {returncode}")
        return
    logger.info(f"Stopping process with SIGTERM, waiting {timeout}")
    process.terminate()
    try:
        returncode = await asyncio.wait_for(
            process.wait(), timeout=timeout.total_seconds()
        )
        logger.info(f"Process has exited after SIGTERM with {returncode}")
    except TimeoutError:
        logger.info(f"Process hasn't exited after {timeout}, SIGKILL'ing...")
        process.kill()


def _only_arg_from_filter(only: Optional[OnlyFilter]) -> List[str]:
    if isinstance(only, TargetType):
        if only == TargetType.MAC:
            return []
        return ["--only", only.value]
    elif isinstance(only, ECIDFilter):
        return ["--only", f"ecid:{only.ecid}"]
    return []


def parse_json_line(line: bytes) -> Dict[str, Union[int, str]]:
    decoded_line = line.decode()
    try:
        return json.loads(decoded_line)
    except json.JSONDecodeError:
        raise IdbJsonException(f"Failed to parse json from: {decoded_line}")


async def _extract_companion_report_from_spawned_companion(
    stream: asyncio.StreamReader,
) -> Dict[str, Union[int, str]]:
    # The first line of stdout should contain launch info,
    # otherwise something bad has happened
    line = await stream.readline()
    logging.debug(f"Read line from companion: {line}")
    update = parse_json_line(line)
    logging.debug(f"Got update from companion: {update}")
    return update


async def _extract_port_from_spawned_companion(stream: asyncio.StreamReader) -> int:
    update = await _extract_companion_report_from_spawned_companion(stream=stream)
    return int(update["grpc_port"])


async def _extract_domain_sock_from_spawned_companion(
    stream: asyncio.StreamReader,
) -> str:
    update = await _extract_companion_report_from_spawned_companion(stream=stream)
    return str(update["grpc_path"])


@dataclass(frozen=True)
class CompanionServerConfig:
    udid: str
    only: OnlyFilter
    log_file_path: Optional[str]
    cwd: Optional[str]
    tmp_path: Optional[str]
    reparent: bool


class Companion(CompanionBase):
    def __init__(
        self, companion_path: str, device_set_path: Optional[str], logger: Logger
    ) -> None:
        self._companion_path = companion_path
        self._device_set_path = device_set_path
        self._logger = logger

    @asynccontextmanager
    async def _start_companion_command(
        self, arguments: List[str]
    ) -> AsyncGenerator[asyncio.subprocess.Process, None]:
        cmd: List[str] = [self._companion_path]
        device_set_path = self._device_set_path
        if device_set_path is not None:
            cmd.extend(["--device-set-path", device_set_path])
        cmd.extend(arguments)
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=subprocess.PIPE,
            stderr=(
                None
                if self._logger.getEffectiveLevel() <= LOG_LEVEL_DEBUG
                else subprocess.DEVNULL
            ),
        )
        logger = self._logger.getChild(f"{process.pid}:{' '.join(arguments)}")
        logger.info("Launched process")
        try:
            yield process
        finally:
            await _terminate_process(
                process=process,
                timeout=DEFAULT_COMPANION_TEARDOWN_TIMEOUT,
                logger=logger,
            )

    async def _run_companion_command(
        self, arguments: List[str], timeout: Optional[timedelta]
    ) -> str:
        timeout = timeout if timeout is not None else DEFAULT_COMPANION_COMMAND_TIMEOUT
        async with self._start_companion_command(arguments=arguments) as process:
            try:
                (output, _) = await asyncio.wait_for(
                    process.communicate(), timeout=timeout.total_seconds()
                )
                if process.returncode != 0:
                    raise IdbException(f"Failed to run {arguments}")
                self._logger.info(f"Ran {arguments} successfully.")
                return output.decode()
            except asyncio.TimeoutError:
                raise IdbException(
                    f"Timed out after {timeout} secs on command {' '.join(arguments)}"
                )

    async def _run_udid_command(
        self,
        udid: str,
        command: str,
        timeout: Optional[timedelta],
        extra_arguments: Optional[Sequence[str]] = None,
    ) -> str:
        arguments = [f"--{command}", udid]
        if extra_arguments is not None:
            arguments.extend(extra_arguments)
        return await self._run_companion_command(
            arguments=[f"--{command}", udid], timeout=timeout
        )

    def _log_file_path(self, target_udid: str) -> str:
        os.makedirs(name=IDB_LOGS_PATH, exist_ok=True)
        return IDB_LOGS_PATH + "/" + target_udid

    async def _spawn_server(
        self,
        config: CompanionServerConfig,
        bind_arguments: List[str],
    ) -> Tuple[asyncio.subprocess.Process, str]:
        if os.getuid() == 0:
            logging.warning(
                "idb should not be run as root. "
                "Listing available targets on this host and spawning "
                "companions will not work"
            )
        arguments: List[str] = (
            [
                self._companion_path,
                "--udid",
                config.udid,
            ]
            + bind_arguments
            + _only_arg_from_filter(config.only)
        )
        log_file_path = config.log_file_path
        if log_file_path is None:
            log_file_path = self._log_file_path(config.udid)
        device_set_path = self._device_set_path
        if device_set_path is not None:
            arguments.extend(["--device-set-path", device_set_path])

        env = dict(os.environ)
        if config.tmp_path:
            env["TMPDIR"] = config.tmp_path

        with open(log_file_path, "a") as log_file:
            process = await asyncio.create_subprocess_exec(
                *arguments,
                stdout=asyncio.subprocess.PIPE,
                stdin=asyncio.subprocess.PIPE if config.reparent else None,
                stderr=log_file,
                cwd=config.cwd,
                env=env,
                preexec_fn=os.setpgrp if config.reparent else None,
            )
            logging.debug(f"started companion at process id {process.pid}")
            return (process, log_file_path)

    async def spawn_tcp_server(
        self,
        config: CompanionServerConfig,
        port: Optional[int],
        tls_cert_path: Optional[str] = None,
    ) -> Tuple[asyncio.subprocess.Process, int]:
        bind_arguments = ["--grpc-port", str(port) if port is not None else "0"]
        if tls_cert_path is not None:
            bind_arguments.extend(["--tls-cert-path", tls_cert_path])
        (process, log_file_path) = await self._spawn_server(
            config=config,
            bind_arguments=bind_arguments,
        )
        stdout = none_throws(process.stdout)
        try:
            extracted_port = await _extract_port_from_spawned_companion(stdout)
        except Exception as e:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, couldn't read port output "
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            ) from e
        if extracted_port == 0:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, port zero is invalid "
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        if port is not None and extracted_port != port:
            raise CompanionSpawnerException(
                "Failed to spawn companion, invalid port "
                f"(expected {port} got {extracted_port})"
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        return (process, extracted_port)

    async def spawn_domain_sock_server(
        self, config: CompanionServerConfig, path: str
    ) -> asyncio.subprocess.Process:
        (process, log_file_path) = await self._spawn_server(
            config=config, bind_arguments=["--grpc-domain-sock", path]
        )
        stdout = none_throws(process.stdout)
        try:
            extracted_path = await _extract_domain_sock_from_spawned_companion(stdout)
        except Exception as e:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, couldn't read port "
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            ) from e
        if not extracted_path:
            raise CompanionSpawnerException(
                f"Failed to spawn companion, no extracted path"
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        if extracted_path != path:
            raise CompanionSpawnerException(
                "Failed to spawn companion, extracted path is not correct "
                f"(expected {path} got {extracted_path})"
                f"stderr: {get_last_n_lines(log_file_path, 30)}"
            )
        return process

    @log_call()
    async def create(
        self, device_type: str, os_version: str, timeout: Optional[timedelta] = None
    ) -> TargetDescription:
        output = await self._run_companion_command(
            arguments=["--create", f"{device_type},{os_version}"], timeout=timeout
        )
        return target_description_from_json(output.splitlines()[-1])

    @log_call()
    async def boot(
        self, udid: str, verify: bool = True, timeout: Optional[timedelta] = None
    ) -> None:
        await self._run_udid_command(
            udid=udid,
            command="boot",
            timeout=timeout,
            extra_arguments=["--verify-booted", "1" if verify else "0"],
        )

    @asynccontextmanager
    async def boot_headless(
        self, udid: str, verify: bool = True, timeout: Optional[timedelta] = None
    ) -> AsyncGenerator[None, None]:
        async with self._start_companion_command(
            [
                "--headless",
                "1",
                "--boot",
                udid,
                "--verify-booted",
                "1" if verify else "0",
            ]
        ) as process:
            # The first line written to stdout is information about the booted sim.
            data = await asyncio.wait_for(
                none_throws(process.stdout).readline(),
                timeout=None if timeout is None else timeout.total_seconds(),
            )
            line = data.decode()
            target = target_description_from_json(line)
            self._logger.info(f"{target} is now booted")
            yield None
            self._logger.info(f"Done with {target}. Shutting down.")

    @log_call()
    async def shutdown(self, udid: str, timeout: Optional[timedelta] = None) -> None:
        await self._run_udid_command(udid=udid, command="shutdown", timeout=timeout)

    @log_call()
    async def erase(
        self, udid: str, timeout: timedelta = DEFAULT_ERASE_COMMAND_TIMEOUT
    ) -> None:
        await self._run_udid_command(udid=udid, command="erase", timeout=timeout)

    @log_call()
    async def clone(
        self,
        udid: str,
        destination_device_set: Optional[str] = None,
        timeout: Optional[timedelta] = None,
    ) -> TargetDescription:
        arguments = ["--clone", udid]
        if destination_device_set is not None:
            arguments.extend(["--clone-destination-set", destination_device_set])
        output = await self._run_companion_command(arguments=arguments, timeout=timeout)
        return target_description_from_json(output.splitlines()[-1])

    @log_call()
    async def delete(
        self, udid: Optional[str], timeout: Optional[timedelta] = None
    ) -> None:
        await self._run_udid_command(
            udid=udid if udid is not None else "all", command="delete", timeout=timeout
        )

    @log_call()
    async def clean(self, udid: str, timeout: Optional[timedelta] = None) -> None:
        await self._run_udid_command(udid=udid, command="clean", timeout=timeout)

    @log_call()
    async def list_targets(
        self, only: Optional[OnlyFilter] = None, timeout: Optional[timedelta] = None
    ) -> List[TargetDescription]:
        arguments = ["--list", "1"] + _only_arg_from_filter(only=only)
        output = await self._run_companion_command(arguments=arguments, timeout=timeout)
        return [
            target_description_from_json(data=line.strip())
            for line in output.splitlines()
            if len(line.strip())
        ]

    async def tail_targets(
        self, only: Optional[OnlyFilter] = None
    ) -> AsyncGenerator[List[TargetDescription], None]:
        arguments = ["--notify", "stdout"] + _only_arg_from_filter(only=only)
        async with self._start_companion_command(arguments=arguments) as process:
            async for line in none_throws(process.stdout):
                yield target_descriptions_from_json(data=line.decode().strip())

    @log_call()
    async def target_description(
        self,
        udid: Optional[str] = None,
        only: Optional[OnlyFilter] = None,
        timeout: Optional[timedelta] = None,
    ) -> TargetDescription:
        all_details = await self.list_targets(only=only, timeout=timeout)
        details = all_details
        if udid is not None:
            details = [target for target in all_details if target.udid == udid]
        if len(details) > 1:
            raise IdbException(f"More than one device info found {details}")
        if len(details) == 0:
            raise IdbException(f"No device info found, got {all_details}")
        return details[0]

    @asynccontextmanager
    async def unix_domain_server(
        self, udid: str, path: str, only: Optional[OnlyFilter] = None
    ) -> AsyncGenerator[str, None]:
        async with self._start_companion_command(
            ["--udid", udid, "--grpc-domain-sock", path]
            + _only_arg_from_filter(only=only)
        ) as process:
            line = await none_throws(process.stdout).readline()
            output = parse_json_line(line)
            grpc_path = output.get("grpc_path")
            if grpc_path is None:
                raise IdbException(f"No grpc_path in {line}")
            self._logger.info(f"Started domain sock server on {grpc_path}")
            # pyre-fixme[7]: Expected `AsyncGenerator[str, None]` but got
            #  `AsyncGenerator[Union[int, str], None]`.
            yield grpc_path
