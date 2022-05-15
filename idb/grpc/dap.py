#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import asyncio
import logging
from asyncio import StreamReader, StreamWriter
from typing import AsyncGenerator, Optional

from idb.common.types import IdbException
from idb.grpc.idb_grpc import CompanionServiceStub
from idb.grpc.idb_pb2 import DapRequest, DapResponse
from idb.grpc.stream import Stream
from idb.utils.contextlib import asynccontextmanager
from idb.utils.typing import none_throws


class RemoteDapServer:
    """
    Manage the connection to the remote dap server spawn by the companion
    """

    def __init__(
        self,
        stream: Stream[DapRequest, DapResponse],
        logger: logging.Logger,
    ) -> None:
        self._stream = stream
        self.logger = logger

    @staticmethod
    @asynccontextmanager
    async def start(
        stub: CompanionServiceStub, logger: logging.Logger, pkg_id: str
    ) -> AsyncGenerator["RemoteDapServer", None]:
        """
        Created a RemoteDapServer starting a new grpc stream and sending a start dap server request to companion
        """
        logger.info("Starting dap connection")
        async with stub.dap.open() as stream:
            await stream.send_message(
                DapRequest(start=DapRequest.Start(debugger_pkg_id=pkg_id))
            )

            response = await stream.recv_message()
            logger.debug(f"Dap response after start request: {response}")
            if response and response.started:
                logger.info("Dap stream ready to receive messages")
                dap_server = RemoteDapServer(
                    stream=stream,
                    logger=logger,
                )
                try:
                    yield dap_server
                finally:
                    await dap_server.__stop()
            else:
                logger.error(f"Starting dap server failed! {response}")
                raise IdbException("Failed to spawn dap server.")

        logger.info("Dap grpc stream is closed.")

    async def pipe(
        self,
        input_stream: StreamReader,
        output_stream: StreamWriter,
        stop: asyncio.Event,
    ) -> None:
        """
        Pipe stdin and stdout to remote dap server
        """
        read_future: Optional[asyncio.Future[StreamReader]] = None
        write_future: Optional[asyncio.Future[StreamWriter]] = None
        stop_future = asyncio.ensure_future(stop.wait())
        while True:
            if read_future is None:
                read_future = asyncio.ensure_future(self._stream.recv_message())
            if write_future is None:
                write_future = asyncio.ensure_future(
                    read_next_dap_protocol_message(input_stream)
                )

            done, pending = await asyncio.wait(
                [read_future, write_future, stop_future],
                return_when=asyncio.FIRST_COMPLETED,
            )

            if stop_future in done:
                self.logger.debug("Received stop command! Closing stream...")
                read_future.cancel()
                self.logger.debug("Read future cancelled!")
                write_future.cancel()
                self.logger.debug("Write future cancelled!")
                break

            if write_future in done:
                data = none_throws(write_future.result())
                write_future = None
                await self._stream.send_message(
                    DapRequest(pipe=DapRequest.Pipe(data=data))
                )

            if read_future in done:
                self.logger.debug("Received a message from companion.")
                result = none_throws(read_future.result())
                read_future = None
                if result is None:
                    # Reached the end of the stream
                    break
                output_stream.write(result.stdout.data)

    async def __stop(self) -> None:
        """
        Stop remote dap server and end grpc stream
        """
        self.logger.debug("Sending stop dap request to close the stream.")
        await self._stream.send_message(DapRequest(stop=DapRequest.Stop()))
        await self._stream.end()

        response = await self._stream.recv_message()

        if response and not response.stopped:
            self.logger.error(f"Dap server failed to stop: {response}")
        else:
            self.logger.info(f"Dap server successfully stopped: {response}")


async def read_next_dap_protocol_message(stream: StreamReader) -> bytes:
    content_length = await stream.readuntil(b"\r\n\r\n")
    length = content_length.decode("utf-8").split(" ")[1]
    body = await stream.read(int(length))
    return content_length + body
