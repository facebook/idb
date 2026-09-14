# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import json
import os
import signal
import struct
import tempfile
import uuid
import zlib
from pathlib import Path

from .harness import artifact_directory, IdbEndToEndTestCase, run
from .recording import Recording


def png_dimensions(data: bytes) -> tuple[int, int]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Expected a PNG image")
    return struct.unpack(">II", data[16:24])


def png_image_data(path: Path) -> bytes:
    data = path.read_bytes()
    png_dimensions(data)
    compressed = bytearray()
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        if data[offset + 4 : offset + 8] == b"IDAT":
            compressed.extend(data[offset + 8 : offset + 8 + length])
        offset += length + 12
    return zlib.decompress(compressed)


class RecordingTests(IdbEndToEndTestCase):
    async def start_recording(self, encoding: str = "mjpeg") -> Recording:
        artifacts = artifact_directory()
        if artifacts is None:
            artifacts = Path(tempfile.mkdtemp(prefix="idb-recording-test-"))
        recording = Recording(
            Path(os.environ["IDB_E2E_RECORDER_PATH"]),
            self.udid,
            self.environment.device_set_path,
            artifacts,
            f"idb-recording-test-{uuid.uuid4().hex}",
            encoding=encoding,
        )
        self.addCleanup(recording.trace.close)
        self.addCleanup(recording.stop)
        await recording.wait_until_ready()
        self.assertTrue(recording.ready, recording.log.read_text(errors="replace"))
        return recording

    async def crop_bar(self, image: Path, height: int, y: int) -> bytes:
        width, _ = png_dimensions(image.read_bytes())
        cropped = image.with_name(f"{image.stem}-bar-{y}.png")
        self.addCleanup(cropped.unlink, missing_ok=True)
        # sips centers the crop at offset (0, 0); inset each bar to avoid that default.
        completed = await run(
            [
                "sips",
                "--cropOffset",
                str(y + 1),
                "1",
                "--cropToHeightWidth",
                str(height - 2),
                str(width - 2),
                str(image),
                "--out",
                str(cropped),
            ],
            timeout=30,
        )
        self.assertEqual(completed.returncode, 0, completed.error_text)
        self.assertEqual(png_dimensions(cropped.read_bytes()), (width - 2, height - 2))
        return png_image_data(cropped)

    async def test_recording_applies_test_and_command_bars(self) -> None:
        screen = await self.idb("screenshot", "-")
        _, screen_height = png_dimensions(screen.stdout)
        recording = await self.start_recording()
        before = await recording.screenshot()
        self.assertIsNotNone(before)
        recording.start_test(self.id())
        test_image = await recording.screenshot()
        self.assertIsNotNone(test_image)
        recording.command(["idb", "ui", "wait", "General"])
        command_image = await recording.screenshot()
        self.assertIsNotNone(command_image)
        await asyncio.to_thread(recording.stop)

        report = json.loads(recording.video.with_suffix(".mov.json").read_text())
        self.assertEqual(report["encoding"], "mjpeg")
        self.assertGreater(report["duration"], 0)
        self.assertGreater(recording.video.stat().st_size, 0)
        assert (
            before is not None and test_image is not None and command_image is not None
        )
        width, height = png_dimensions(command_image.read_bytes())
        self.assertEqual((report["width"], report["height"]), (width, height))
        bar_height = (height - int(screen_height * 0.5)) // 2
        self.assertGreater(bar_height, 0)
        self.assertTrue(
            await self.crop_bar(before, bar_height, 0)
            != await self.crop_bar(test_image, bar_height, 0),
            "Starting a test did not change the top bar",
        )
        self.assertTrue(
            await self.crop_bar(test_image, bar_height, 0)
            == await self.crop_bar(command_image, bar_height, 0),
            "Running a command changed the test title in the top bar",
        )
        self.assertTrue(
            await self.crop_bar(test_image, bar_height, height - bar_height)
            != await self.crop_bar(command_image, bar_height, height - bar_height),
            "Running a command did not change the bottom bar",
        )

    async def test_recording_chooses_a_working_encoder(self) -> None:
        recording = await self.start_recording(encoding="auto")
        recording.start_test(self.id())
        for index in range(30):
            recording.send("chapter", text=f"Step {index}")
        self.assertIsNotNone(await recording.screenshot())
        await asyncio.to_thread(recording.stop)
        self.assertEqual(
            recording.process.returncode, 0, recording.log.read_text(errors="replace")
        )
        report = json.loads(recording.video.with_suffix(".mov.json").read_text())
        self.assertIn(report["encoding"], {"hevc", "mjpeg"})
        if report["encoding"] == "mjpeg":
            self.assertIn("Recording with hevc failed:", recording.log.read_text())
        self.assertGreater(report["duration"], 0)

    async def test_recording_finalizes_after_sigterm(self) -> None:
        recording = await self.start_recording()
        recording.start_test(self.id())
        self.assertIsNotNone(await recording.screenshot())
        recording.process.send_signal(signal.SIGTERM)
        await asyncio.to_thread(recording.process.wait, timeout=30)
        self.assertEqual(
            recording.process.returncode, 0, recording.log.read_text(errors="replace")
        )
        report = json.loads(recording.video.with_suffix(".mov.json").read_text())
        self.assertGreater(report["duration"], 0)

    async def test_streaming_stops_at_stdin_eof(self) -> None:
        directory = self.make_temporary_directory()
        destination = directory / "frames.bgra"
        log_path = directory / "stream.log"
        with log_path.open("wb") as log:
            process = await asyncio.create_subprocess_exec(
                os.environ["IDB_E2E_RECORDER_PATH"],
                "stream",
                str(destination),
                "--set",
                str(self.environment.device_set_path),
                "--udid",
                self.udid,
                "--encoding",
                "bgra",
                "--scale",
                "0.1",
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=log,
            )
        try:
            async with asyncio.timeout(30):
                while not destination.exists() or destination.stat().st_size == 0:
                    self.assertIsNone(
                        process.returncode, log_path.read_text(errors="replace")
                    )
                    await asyncio.sleep(0.1)
            assert process.stdin is not None
            process.stdin.close()
            await asyncio.wait_for(process.wait(), 30)
            self.assertEqual(
                process.returncode, 0, log_path.read_text(errors="replace")
            )
        finally:
            if process.returncode is None:
                process.kill()
            await process.wait()

    async def test_recording_rejects_incompatible_container_and_transport(self) -> None:
        destination = self.make_temporary_directory() / "video.mp4"
        common = ["--set", str(self.environment.device_set_path), "--udid", self.udid]
        examples = [
            (
                ["record", str(destination), "--encoding", "auto"],
                "require a .mov output",
            ),
            (
                [
                    "stream",
                    str(destination),
                    "--encoding",
                    "bgra",
                    "--transport",
                    "annex-b",
                ],
                "only valid with h264 or hevc",
            ),
        ]
        for arguments, error in examples:
            completed = await run(
                [os.environ["IDB_E2E_RECORDER_PATH"], *arguments, *common], timeout=30
            )
            self.assertNotEqual(completed.returncode, 0, arguments)
            self.assertIn(error, completed.error_text)
            self.assertFalse(destination.exists())
