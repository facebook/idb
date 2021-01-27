#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import json
import logging
import subprocess
from datetime import timedelta
from logging import Logger, DEBUG as LOG_LEVEL_DEBUG
from typing import AsyncGenerator, Dict, List, Optional, Sequence, Union

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
        return ["--only", "simulator" if only is TargetType.SIMULATOR else "device"]
    elif isinstance(only, ECIDFilter):
        return ["--only", f"ecid:{only.ecid}"]
    return []


def parse_json_line(line: bytes) -> Dict[str, Union[int, str]]:
    decoded_line = line.decode()
    try:
        return json.loads(decoded_line)
    except json.JSONDecodeError:
        raise IdbJsonException(f"Failed to parse json from: {decoded_line}")


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
