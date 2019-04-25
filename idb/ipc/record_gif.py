#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio

from idb.cli.helper.gif_helper import GIFHelper
from idb.common.companion import CompanionClient
from idb.grpc.idb_pb2 import ScreenshotRequest


async def client(
    client: CompanionClient, stop: asyncio.Event, output_file: str, fps: int
) -> str:
    gif_helper = GIFHelper()
    time_to_take_screenshot = 1.0 / fps
    while not stop.is_set():
        screenshot_response = await client.stub.screenshot(ScreenshotRequest())
        asyncio.get_event_loop().run_in_executor(
            None,
            gif_helper.save_image_to_tmp_folder,  # pyre-ignore
            screenshot_response.image_data,
            client.udid,
        )
        await asyncio.wait(
            [stop.wait(), asyncio.sleep(time_to_take_screenshot)],
            return_when=asyncio.FIRST_COMPLETED,
        )
    return await asyncio.get_event_loop().run_in_executor(
        None, gif_helper.save_gif_to_path, fps, output_file, client.udid  # pyre-ignore
    )
