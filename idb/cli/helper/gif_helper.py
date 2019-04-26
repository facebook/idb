#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import logging
import os
import time
from io import BytesIO
from typing import Optional


# Tmp directory where we will store the files.
SCREENSHOT_DIR = "/tmp/idb/screenshot/"

SCREENSHOT_WIDTH = 300
UDID_PREFIX_LENGTH = 5
UDID_DUMMY = "udid_dummy"
DEFAULT_GIF_FILE_NAME = "screenshot.gif"


class GIFHelper:
    def __init__(self) -> None:
        self._logger: logging.Logger = logging.getLogger("GIFHelper")

    def save_image_to_tmp_folder(self, image_data: bytes, udid: Optional[str]) -> None:
        try:
            from PIL import Image

            image = Image.open(BytesIO(image_data))
            image.convert("RGB")
            current_width, current_height = image.size
            resized_image = image.resize(
                (
                    SCREENSHOT_WIDTH,
                    int(current_height / current_width * SCREENSHOT_WIDTH),
                ),
                Image.ANTIALIAS,
            )
            if udid is None:
                udid = UDID_DUMMY
            # Save the image with time, so we can then sort them according to time
            file_path = os.path.join(
                SCREENSHOT_DIR, f"{udid[:UDID_PREFIX_LENGTH]}-{str(time.time())}.png"
            )
            if not os.path.exists(SCREENSHOT_DIR):
                os.makedirs(SCREENSHOT_DIR)
            resized_image.save(file_path, "png")
            self._logger.info("Saved screenshot")
        except ImportError:
            self._logger.error("Pillow not present on Macos")

    def save_screenshots_to_gif(self, fps: int, udid: Optional[str]) -> None:
        try:
            import imageio

            if udid is None:
                udid = UDID_DUMMY
            gif_file_path = os.path.join(SCREENSHOT_DIR, DEFAULT_GIF_FILE_NAME)
            with imageio.get_writer(gif_file_path, mode="I", fps=fps) as writer:
                for file_name in sorted(os.listdir(SCREENSHOT_DIR)):
                    if (not file_name.endswith(".png")) or (
                        not file_name.startswith(f"{udid[:UDID_PREFIX_LENGTH]}")
                    ):
                        continue
                    image_file_path = os.path.join(SCREENSHOT_DIR, file_name)
                    image = imageio.imread(image_file_path)
                    writer.append_data(image)
                    os.remove(image_file_path)
            self._logger.info(f"Saved gif to: {gif_file_path}")
        except ImportError:
            self._logger.error(f"imageio is not present on Macos")

    def save_gif_to_path(self, fps: int, file_path: str, udid: Optional[str]) -> str:
        if udid is None:
            udid = UDID_DUMMY
        self.save_screenshots_to_gif(fps, udid)
        gif_file_path = os.path.join(SCREENSHOT_DIR, DEFAULT_GIF_FILE_NAME)
        try:
            os.rename(gif_file_path, file_path)
        except Exception as e:
            print(f"{e}")
        self._logger.info(f"Moved gif to : {file_path}")
        return gif_file_path
