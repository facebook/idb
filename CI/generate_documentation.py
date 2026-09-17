# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Turn one end-to-end run's artifacts into the demos the website publishes.

python3 -m CI.generate_documentation --artifacts-dir "$RUNNER_TEMP/e2e" --output docs

Reads the command trace the suite wrote, keeps the commands its documented
demos named, and writes a manifest beside the media the website needs. A demo
the suite no longer performs, or performed and failed, is an error: nothing is
written and the run fails, so broken documentation is never published.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Sequence

try:
    from EndToEndTests.documentation import DOCUMENTED_DEMOS, test_identity
except ImportError:
    # A build that imports both packages by their path in the repository.
    from ..EndToEndTests.documentation import DOCUMENTED_DEMOS, test_identity

TRACE_SUFFIX = "-commands.jsonl"
MANIFEST_NAME = "demos.json"
MEDIA_DIRECTORY = "media"

# The suite runs this client against a companion it cannot change, so nothing
# it records documents the client the website is about.
READ_ONLY_CLIENT_ENV = "IDB_E2E_READ_ONLY_CLIENT"

# The one encoding every browser decodes, and the type it must be served as.
# The container comes from the recording's own extension rather than from the
# encoding, so a recording is only published when the two agree.
PUBLISHABLE_ENCODING = "h264"
PUBLISHABLE_TYPE = "video/mp4"
VIDEO_TYPES = {".mp4": "video/mp4", ".mov": "video/quicktime"}


class GenerationError(Exception):
    """The run's artifacts cannot produce documentation at all."""


def within(offset: float, duration: float | None) -> float:
    """An offset the player can seek to.

    Offsets are derived from the wall clock the trace recorded, and the
    recording covers a little less than that: it starts once the recorder has
    a frame. An offset past the end of the video would seek nowhere, so the
    last frame stands in for it.
    """
    if offset < 0:
        return 0.0
    if duration is not None and offset > duration:
        return duration
    return offset


@dataclass(frozen=True)
class Video:
    """The run's recording, in a form the website can play."""

    name: str
    type: str
    width: int
    height: int
    duration: float

    def as_json(self) -> dict[str, Any]:
        return {
            "source": f"{MEDIA_DIRECTORY}/{self.name}",
            "type": self.type,
            "width": self.width,
            "height": self.height,
            "duration": round(self.duration, 3),
        }


@dataclass(frozen=True)
class Command:
    """One command a demo named, and what it printed."""

    step: str
    argv: tuple[str, ...]
    returncode: int
    start: float
    seconds: float
    stdout: dict[str, Any]
    stderr: dict[str, Any]

    def as_json(self, duration: float | None) -> dict[str, Any]:
        return {
            "step": self.step,
            "argv": list(self.argv),
            "returncode": self.returncode,
            "start": round(within(self.start, duration), 3),
            "seconds": round(self.seconds, 3),
            "stdout": self.stdout,
            "stderr": self.stderr,
        }


@dataclass(frozen=True)
class Demo:
    """One demo as the run performed it."""

    slug: str
    title: str
    summary: str
    test: str
    status: str
    start: float
    end: float
    screenshots: tuple[str, ...]
    commands: tuple[Command, ...]

    def as_json(self, poster: str | None, duration: float | None) -> dict[str, Any]:
        return {
            "slug": self.slug,
            "title": self.title,
            "summary": self.summary,
            "test": self.test,
            "start": round(within(self.start, duration), 3),
            "end": round(within(self.end, duration), 3),
            "poster": poster,
            "commands": [command.as_json(duration) for command in self.commands],
        }


@dataclass
class _Performance:
    """A demo being read out of the trace, until its test finishes."""

    slug: str
    title: str
    summary: str
    test: str
    start: float
    screenshots: list[str] = field(default_factory=list)
    commands: list[Command] = field(default_factory=list)

    def finished(self, status: str, end: float) -> Demo:
        return Demo(
            slug=self.slug,
            title=self.title,
            summary=self.summary,
            test=self.test,
            status=status,
            start=self.start,
            end=end,
            screenshots=tuple(self.screenshots),
            commands=tuple(self.commands),
        )


def read_events(trace: Path) -> list[dict[str, Any]]:
    """The events one trace holds, or what makes it unreadable as a trace.

    Every trace the run left behind is read to find the one that recorded
    demos, so a file that is not a trace at all is reported as the file it is
    rather than raised through the generator as a decoder's traceback.
    """
    events = []
    for number, line in enumerate(trace.read_text().splitlines(), start=1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except ValueError as error:
            raise GenerationError(
                f"{trace.name} line {number} is not a trace event: {error}"
            ) from error
        if not isinstance(event, dict) or not isinstance(event.get("event"), str):
            raise GenerationError(f"{trace.name} line {number} names no event")
        events.append(event)
    return events


def origin_of(events: Sequence[dict[str, Any]]) -> float:
    """The wall clock the video starts at, which every offset is measured from."""
    for event in events:
        if event["event"] == "recording_started":
            return float(event["time"])
    return float(events[0]["time"]) if events else 0.0


def command_of(event: dict[str, Any], origin: float) -> Command:
    seconds = float(event.get("seconds", 0.0))
    return Command(
        step=event["step"],
        argv=tuple(event["argv"]),
        returncode=int(event["returncode"]),
        start=float(event["time"]) - origin - seconds,
        seconds=seconds,
        stdout=event["stdout"],
        stderr=event["stderr"],
    )


def read_demos(events: Sequence[dict[str, Any]]) -> list[Demo]:
    """The demos the run performed, in the order the trace records them.

    A demo can only be read while the test performing it runs, so one that
    begins where another has not finished is a trace nothing can be read out
    of: taking the second would silently drop everything the first collected.
    """
    origin = origin_of(events)
    demos: list[Demo] = []
    performing: _Performance | None = None
    for event in events:
        kind = event["event"]
        # The trace of a build that imports the suite by its path in the
        # repository names the same test at greater length.
        identity = test_identity(event["test"]) if "test" in event else None
        if kind == "demo":
            if performing is not None:
                raise GenerationError(
                    f"{performing.slug} is still being performed where "
                    f"{event['slug']} begins, so neither can be published"
                )
            performing = _Performance(
                slug=event["slug"],
                title=event["title"],
                summary=event["summary"],
                test=identity or "",
                start=float(event["time"]) - origin,
            )
        elif performing is None or identity != performing.test:
            continue
        elif kind == "command_finished" and "step" in event:
            performing.commands.append(command_of(event, origin))
        elif kind == "screenshot":
            performing.screenshots.append(event["path"])
        elif kind == "test_finished":
            demos.append(
                performing.finished(event["status"], float(event["time"]) - origin)
            )
            performing = None
    return demos


def problems(demos: Sequence[Demo]) -> list[str]:
    """Everything that makes this run unfit to document, worst case listed once."""
    found: dict[str, Demo] = {}
    repeated: set[str] = set()
    issues: list[str] = []
    for demo in demos:
        if demo.slug in found:
            repeated.add(demo.slug)
            continue
        found[demo.slug] = demo
        published = DOCUMENTED_DEMOS.get(demo.slug)
        if published is None:
            issues.append(f"{demo.slug} is not a demo the website publishes")
        elif published != demo.test:
            issues.append(
                f"{demo.slug} is published as {published} but was performed by "
                f"{demo.test}"
            )
        if demo.status != "passed":
            issues.append(f"{demo.slug} finished {demo.status}, so it cannot be shown")
        if not demo.commands:
            issues.append(f"{demo.slug} named no commands to publish")
    issues.extend(f"{slug} was performed more than once" for slug in repeated)
    issues.extend(
        f"{slug} was not performed by this run"
        for slug in DOCUMENTED_DEMOS
        if slug not in found
    )
    return sorted(issues)


def recording_beside(trace: Path) -> tuple[Path, Path] | None:
    """The recording a trace was written alongside, whatever container it is in."""
    prefix = trace.name.removesuffix(TRACE_SUFFIX)
    for suffix in VIDEO_TYPES:
        video = trace.parent / f"{prefix}{suffix}"
        # The recorder appends to the whole path rather than replacing the
        # extension, and only writes the report once the recording decodes.
        report = Path(f"{video}.json")
        if video.is_file() and report.is_file():
            return video, report
    return None


def read_video(trace: Path) -> Video | None:
    """The recording beside a trace, when the website can play it."""
    beside = recording_beside(trace)
    if beside is None:
        print(f"No recording beside {trace.name}", file=sys.stderr)
        return None
    video, report = beside
    # The report is written by the recorder as it finalises, so one that cannot
    # be read means the recording cannot either. The transcript is still worth
    # publishing without it, as it is for a run that recorded nothing.
    try:
        described = json.loads(report.read_text())
        encoding = described["encoding"]
        recording = Video(
            name=video.name,
            type=VIDEO_TYPES[video.suffix],
            width=int(described["width"]),
            height=int(described["height"]),
            duration=float(described["duration"]),
        )
    except (KeyError, TypeError, ValueError) as error:
        print(f"{report.name} does not describe a recording: {error}", file=sys.stderr)
        return None
    if encoding != PUBLISHABLE_ENCODING:
        print(
            f"{video.name} is {encoding}, which browsers do not agree on; record "
            f"with IDB_E2E_RECORDER_ENCODING={PUBLISHABLE_ENCODING} to publish it",
            file=sys.stderr,
        )
        return None
    if recording.type != PUBLISHABLE_TYPE:
        print(
            f"{video.name} is {encoding} in a {recording.type} container, which "
            "browsers will not play; nothing but the container is wrong with it",
            file=sys.stderr,
        )
        return None
    return recording


def copy_poster(demo: Demo, artifacts: Path, media: Path) -> str | None:
    """The demo's final screenshot, which stands in for the video that may not exist."""
    for name in reversed(demo.screenshots):
        source = artifacts / name
        if not source.is_file():
            continue
        shutil.copy(source, media / f"{demo.slug}.png")
        return f"{MEDIA_DIRECTORY}/{demo.slug}.png"
    return None


def write(
    output: Path, artifacts: Path, video: Video | None, demos: Sequence[Demo]
) -> None:
    media = output / MEDIA_DIRECTORY
    # The manifest names everything the website serves, so a second run into
    # the same output must leave nothing of the first behind: a renamed or
    # deleted demo's poster would otherwise stay there to be published.
    shutil.rmtree(media, ignore_errors=True)
    media.mkdir(parents=True, exist_ok=True)
    if video is not None:
        shutil.copy(artifacts / video.name, media / video.name)
    duration = None if video is None else video.duration
    manifest = {
        "video": None if video is None else video.as_json(),
        "demos": [
            demo.as_json(copy_poster(demo, artifacts, media), duration)
            for demo in sorted(demos, key=lambda demo: demo.slug)
        ],
    }
    (output / MANIFEST_NAME).write_text(json.dumps(manifest, indent=2) + "\n")


def select_trace(artifacts: Path) -> tuple[Path, list[dict[str, Any]]]:
    """The one trace that recorded demos, of however many the run left behind."""
    performed = [
        (path, events)
        for path, events in (
            (path, read_events(path))
            for path in sorted(artifacts.glob(f"*{TRACE_SUFFIX}"))
        )
        if any(event["event"] == "demo" for event in events)
    ]
    if not performed:
        raise GenerationError(f"No command trace in {artifacts} recorded a demo")
    if len(performed) > 1:
        names = ", ".join(path.name for path, _ in performed)
        raise GenerationError(f"More than one command trace recorded demos: {names}")
    return performed[0]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args(argv)

    if os.environ.get(READ_ONLY_CLIENT_ENV) == "1":
        print(
            f"{READ_ONLY_CLIENT_ENV}=1 documents a client the website is not "
            "about; run the suite without it to document a run",
            file=sys.stderr,
        )
        return 1

    try:
        trace, events = select_trace(arguments.artifacts_dir)
        demos = read_demos(events)
        issues = problems(demos)
        if issues:
            for issue in issues:
                print(issue, file=sys.stderr)
            print(f"Not documenting {trace.name}", file=sys.stderr)
            return 1
        write(arguments.output, arguments.artifacts_dir, read_video(trace), demos)
    except (GenerationError, OSError) as error:
        print(error, file=sys.stderr)
        return 1

    for demo in sorted(demos, key=lambda demo: demo.slug):
        print(demo.slug)
        for command in demo.commands:
            print(f"  {command.step}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
