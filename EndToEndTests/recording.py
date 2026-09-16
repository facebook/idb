# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import asyncio
import json
import os
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any, Sequence


class Recording:
    def __init__(
        self,
        binary: Path,
        udid: str,
        device_set: Path,
        directory: Path,
        prefix: str,
        encoding: str = "auto",
    ) -> None:
        self.directory = directory
        self.prefix = prefix
        self.video = directory / f"{prefix}.mov"
        self.log = directory / f"{prefix}-recorder.log"
        self.screenshots = directory / f"{prefix}-screenshots"
        self.trace = (directory / f"{prefix}-commands.jsonl").open("w")
        self.test = ""
        self.ready = False
        self.error: str | None = None
        self.stopped = False
        self.index = 0
        try:
            with self.log.open("wb") as log:
                self.process = subprocess.Popen(
                    [
                        str(binary),
                        "record",
                        str(self.video),
                        "--udid",
                        udid,
                        "--set",
                        str(device_set),
                        "--encoding",
                        encoding,
                        "--scale",
                        "0.5",
                        "--bar",
                        "top:48",
                        "bottom:48",
                        "--screenshot-dir",
                        str(self.screenshots),
                    ],
                    stdin=subprocess.PIPE,
                    stdout=subprocess.DEVNULL,
                    stderr=log,
                )
        except OSError:
            self.trace.close()
            raise
        self.annotate(self.log, "generic_text_log")
        self.annotate(Path(self.trace.name), "generic_text_log")

    async def wait_until_ready(self) -> None:
        deadline = time.monotonic() + 60
        with self.log.open() as log:
            text = ""
            while time.monotonic() < deadline:
                text += log.read()
                if "Going into PLAYING state." in text:
                    self.ready = True
                    self.event("recording_started")
                    return
                text = text[-256:]
                if self.process.poll() is not None:
                    self.error = f"Recorder exited with {self.process.returncode} before producing frames"
                    break
                await asyncio.sleep(0.1)
            else:
                self.error = "Recorder did not produce frames within 60 seconds"
        self.event("recording_unavailable", reason=self.error)
        await asyncio.to_thread(self.stop)

    def event(self, event: str, **fields: Any) -> None:
        self.trace.write(
            json.dumps(
                {"time": time.time(), "event": event, "test": self.test, **fields}
            )
            + "\n"
        )
        self.trace.flush()

    def send(self, method: str, **params: Any) -> bool:
        if not self.ready or self.process.poll() is not None:
            return False
        assert self.process.stdin is not None
        try:
            self.process.stdin.write(
                (json.dumps({"method": method, "params": params}) + "\n").encode()
            )
            self.process.stdin.flush()
            return True
        except OSError as error:
            self.error = f"Recorder command failed: {error}"
            self.event("recording_error", reason=self.error)
            self.ready = False
            return False

    def start_test(self, name: str) -> None:
        self.test = name
        self.event("test_started")
        title = name.rsplit(".", 1)[-1].removeprefix("test_").replace("_", " ")
        self.send("bar", position="top", content="text", text=title, fit=True)
        self.send("bar", position="bottom", content="text", text="Setup", fit=True)
        self.send("chapter", text=name)

    def finish_test(self, status: str) -> None:
        self.event("test_finished", status=status)
        self.send("bar", position="bottom", content="text", text=status, fit=True)

    def command(self, argv: Sequence[str]) -> None:
        text = shlex.join(argv)
        self.event("command_started", argv=list(argv))
        self.send("bar", position="bottom", content="text", text=text, fit=True)

    async def screenshot(self) -> Path | None:
        self.index += 1
        index = self.index
        if not self.send("screenshot", index=index):
            return None
        source = self.screenshots / f"screenshot_{index}.png"
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if source.is_file():
                destination = self.directory / f"{self.prefix}-screenshot-{index}.png"
                source.replace(destination)
                self.event("screenshot", path=destination.name)
                self.annotate(destination, "screenshot_test_artifact")
                return destination
            if self.process.poll() is not None:
                break
            await asyncio.sleep(0.1)
        self.event("screenshot_unavailable", index=index)
        return None

    def save_screenshot(self, data: bytes) -> None:
        self.index += 1
        destination = self.directory / f"{self.prefix}-screenshot-{self.index}.png"
        destination.write_bytes(data)
        self.event("screenshot", path=destination.name)
        self.annotate(destination, "screenshot_test_artifact")

    def annotate(self, artifact: Path, kind: str) -> None:
        annotations = os.environ.get("TEST_RESULT_ARTIFACT_ANNOTATIONS_DIR")
        if not annotations:
            return
        path = Path(annotations) / f"{artifact.name}.annotation"
        path.parent.mkdir(parents=True, exist_ok=True)
        details = (
            {"artifact_type": 0, "artifact_label": 0}
            if kind == "screenshot_test_artifact"
            else {}
        )
        path.write_text(
            json.dumps({"type": {kind: details}, "description": "idb end-to-end tests"})
            + "\n"
        )

    def stop(self) -> None:
        if self.stopped:
            return
        self.stopped = True
        if self.process.poll() is None:
            self.send("shutdown")
        if self.process.stdin is not None and not self.process.stdin.closed:
            try:
                self.process.stdin.close()
            except OSError as error:
                self.event("recording_error", reason=f"Closing recorder stdin: {error}")
        if self.process.poll() is None:
            try:
                self.process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                self.error = "Recorder did not finalize within 30 seconds"
                self.process.kill()
                self.process.wait()
        report_path = self.video.with_suffix(".mov.json")
        status = (
            "recorded"
            if self.process.returncode == 0 and report_path.is_file()
            else "unavailable"
        )
        self.event(
            "recording_finished",
            status=status,
            returncode=self.process.returncode,
            error=self.error,
        )
        if status == "recorded":
            self.annotate(self.video, "video_recording_test_artifact")
        self.ready = False
