# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Turn one end-to-end run's artifacts into the demos the website publishes.

python3 -m CI.generate_documentation --artifacts-dir "$RUNNER_TEMP/e2e" --output docs

Reads the command trace the suite wrote, keeps the commands its documented
demos named, and cuts each demo its own clip out of the run's recording, so a
demo plays only itself rather than seeking into a recording of the whole
suite. A demo the suite no longer performs, or performed and failed, is an
error: nothing is written and the run fails, so broken documentation is never
published.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
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

# The recorder the suite was pointed at, which is also what cuts the clips: it
# is the one tool that is certain to be on the machine that produced the
# recording, having produced it.
RECORDER_ENV = "IDB_E2E_RECORDER_PATH"

# The one encoding every browser decodes, and the type it must be served as.
# The container comes from the recording's own extension rather than from the
# encoding, so a recording is only published when the two agree.
PUBLISHABLE_ENCODING = "h264"
PUBLISHABLE_TYPE = "video/mp4"
VIDEO_TYPES = {".mp4": "video/mp4", ".mov": "video/quicktime"}

# What each clip keeps either side of the demo, so it does not open on the
# first command already in flight or cut the last one off mid-animation. Both
# are only ever taken out of the demo's own test: a clip that reached into the
# test before or after would show a viewer something no caption describes.
LEAD_SECONDS = 1.0
TAIL_SECONDS = 1.0

# A clip shorter than this is not worth publishing: the controls of a player
# given one cannot be used, and a poster frame says the same thing.
SHORTEST_CLIP_SECONDS = 0.5

# Cutting one demo out of a suite recording decodes and re-encodes a few
# seconds of video. A recorder still running after this is one that is not
# going to finish, and the demo degrades to its poster rather than hanging CI.
CLIP_TIMEOUT_SECONDS = 300


class GenerationError(Exception):
    """The run's artifacts cannot produce documentation at all."""


def within(offset: float, duration: float | None) -> float:
    """An offset the player can seek to.

    Offsets are derived from the wall clock the trace recorded, and a clip
    covers a little less than the interval it was asked for: it begins and
    ends on the frames nearest its bounds. An offset past the end of the clip
    would seek nowhere, so the last frame stands in for it.
    """
    if offset < 0:
        return 0.0
    if duration is not None and offset > duration:
        return duration
    return offset


@dataclass(frozen=True)
class Video:
    """A clip of the run's recording, in a form the website can play."""

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
class Clip:
    """One demo's own clip: what the website plays, and where it came from."""

    offset: float
    video: Video


@dataclass(frozen=True)
class Recording:
    """The run's recording, when it is one clips can be cut out of."""

    path: Path
    duration: float
    started_at: float | None


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

    def as_json(self, clip: Clip | None) -> dict[str, Any]:
        offset = self.start - (0.0 if clip is None else clip.offset)
        duration = None if clip is None else clip.video.duration
        return {
            "step": self.step,
            "argv": list(self.argv),
            "returncode": self.returncode,
            "start": round(within(offset, duration), 3),
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
    began: float
    test_began: float
    test_ended: float
    next_test: float | None
    screenshots: tuple[str, ...]
    commands: tuple[Command, ...]

    def first_command(self) -> float:
        """When the first command this demo publishes was run."""
        return min((command.start for command in self.commands), default=self.began)

    def bounds(self, duration: float) -> tuple[float, float]:
        """The interval of the recording this demo's clip is cut from.

        A demo is marked where its test begins, and a test can spend a long
        time getting an app into the state the demo is about -- terminating it,
        launching it, waiting for it to answer -- none of which the demo is
        about. So the clip opens just before the first command the demo
        publishes rather than where the demo was marked. It is held inside that
        one test at both ends: never before it started, and never into
        whichever test began next.
        """
        start = max(0.0, self.test_began, self.first_command() - LEAD_SECONDS)
        end = self.test_ended + TAIL_SECONDS
        if self.next_test is not None:
            end = min(end, self.next_test)
        return start, min(end, duration)

    def as_json(self, poster: str | None, clip: Clip | None) -> dict[str, Any]:
        offset = 0.0 if clip is None else clip.offset
        duration = None if clip is None else clip.video.duration
        return {
            "slug": self.slug,
            "title": self.title,
            "summary": self.summary,
            "test": self.test,
            "poster": poster,
            "video": None if clip is None else clip.video.as_json(),
            # The website reads a demo as an interval to seek to within a
            # longer recording, and refuses a manifest without one. It is a
            # clip of its own from here on, so the interval it seeks to is the
            # whole of that clip, until the page stops asking for one.
            "start": round(within(self.began - offset, duration), 3),
            "end": round(within(self.test_ended - offset, duration), 3),
            "commands": [command.as_json(clip) for command in self.commands],
        }


@dataclass
class _Performance:
    """A demo being read out of the trace, until its test finishes."""

    slug: str
    title: str
    summary: str
    test: str
    began: float
    test_began: float
    screenshots: list[str] = field(default_factory=list)
    commands: list[Command] = field(default_factory=list)

    def finished(self, status: str, end: float, next_test: float | None) -> Demo:
        return Demo(
            slug=self.slug,
            title=self.title,
            summary=self.summary,
            test=self.test,
            status=status,
            began=self.began,
            test_began=self.test_began,
            test_ended=end,
            next_test=next_test,
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


def origin_of(events: Sequence[dict[str, Any]], recording: Recording | None) -> float:
    """The wall clock the recording's first frame was captured at.

    The recorder reports it, because the harness cannot: it stamps
    `recording_started` where it notices the recorder is up, which trails the
    first frame by however long readiness took to reach and to detect, and
    biases every offset measured from it. A run that recorded nothing, or whose
    recorder could not establish its own media time zero, falls back to that
    event.
    """
    if recording is not None and recording.started_at is not None:
        return recording.started_at
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


def test_starts(events: Sequence[dict[str, Any]], origin: float) -> list[float]:
    """When each test of the run began, in the order the trace records them."""
    return [
        float(event["time"]) - origin
        for event in events
        if event["event"] == "test_started"
    ]


def started_tests(events: Sequence[dict[str, Any]], origin: float) -> dict[str, float]:
    """When the test performing each demo began, by the test's own identity."""
    starts: dict[str, float] = {}
    for event in events:
        if event["event"] != "test_started":
            continue
        identity = test_identity(event["test"]) if "test" in event else ""
        starts.setdefault(identity, float(event["time"]) - origin)
    return starts


def read_demos(events: Sequence[dict[str, Any]], origin: float) -> list[Demo]:
    """The demos the run performed, in the order the trace records them.

    A demo can only be read while the test performing it runs, so one that
    begins where another has not finished is a trace nothing can be read out
    of: taking the second would silently drop everything the first collected.
    """
    boundaries = test_starts(events, origin)
    starts = started_tests(events, origin)
    demos: list[Demo] = []
    performing: _Performance | None = None
    for event in events:
        kind = event["event"]
        at = float(event["time"]) - origin
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
                began=at,
                test_began=starts.get(identity or "", at),
            )
        elif performing is None or identity != performing.test:
            continue
        elif kind == "command_finished" and "step" in event:
            performing.commands.append(command_of(event, origin))
        elif kind == "screenshot":
            performing.screenshots.append(event["path"])
        elif kind == "test_finished":
            after = next((start for start in boundaries if start > at), None)
            demos.append(performing.finished(event["status"], at, after))
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


def read_recording(trace: Path) -> Recording | None:
    """The recording beside a trace, when clips the website can play come out of it."""
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
        recording = Recording(
            path=video,
            duration=float(described["duration"]),
            started_at=(
                None
                if described.get("startedAt") is None
                else float(described["startedAt"])
            ),
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
    if VIDEO_TYPES[video.suffix] != PUBLISHABLE_TYPE:
        print(
            f"{video.name} is {encoding} in a {VIDEO_TYPES[video.suffix]} container, "
            "which browsers will not play; nothing but the container is wrong with it",
            file=sys.stderr,
        )
        return None
    return recording


def read_clip(report: Path, name: str) -> Video | None:
    """What the recorder says it cut, or why the clip cannot be published."""
    try:
        described = json.loads(report.read_text())
        return Video(
            name=name,
            type=PUBLISHABLE_TYPE,
            width=int(described["width"]),
            height=int(described["height"]),
            duration=float(described["duration"]),
        )
    except (KeyError, OSError, TypeError, ValueError) as error:
        print(f"{report.name} does not describe a clip: {error}", file=sys.stderr)
        return None


def cut(
    recorder: Path,
    recording: Recording,
    media: Path,
    slug: str,
    bounds: tuple[float, float],
) -> Clip | None:
    """Cut one demo's clip out of the recording, or say why it has none.

    A demo without a clip still publishes its transcript and poster, so one
    recorder that failed costs that demo its video rather than the whole page.
    """
    start, end = bounds
    if end - start < SHORTEST_CLIP_SECONDS:
        print(
            f"{slug} covers {end - start:.3f} seconds of {recording.path.name}, "
            f"too little to publish as a clip",
            file=sys.stderr,
        )
        return None
    destination = media / f"{slug}.mp4"
    argv = [
        str(recorder),
        "clip",
        "--start",
        f"{start:.3f}",
        "--end",
        f"{end:.3f}",
        str(recording.path),
        str(destination),
    ]
    try:
        finished = subprocess.run(
            argv, capture_output=True, text=True, timeout=CLIP_TIMEOUT_SECONDS
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(
            f"Could not cut {slug} out of {recording.path.name}: {error}",
            file=sys.stderr,
        )
        return None
    if finished.returncode != 0:
        said = (
            finished.stderr.strip() or f"{recorder.name} exited {finished.returncode}"
        )
        print(
            f"Could not cut {slug} out of {recording.path.name}: {said}",
            file=sys.stderr,
        )
        return None
    report = Path(f"{destination}.json")
    video = read_clip(report, destination.name)
    # The manifest names everything the media directory serves, and the
    # recorder's report of a clip is not one of them.
    report.unlink(missing_ok=True)
    if video is None:
        destination.unlink(missing_ok=True)
        return None
    return Clip(offset=start, video=video)


def cut_clips(
    recorder: Path, recording: Recording, demos: Sequence[Demo], media: Path
) -> dict[str, Clip]:
    """A clip per demo the recording could be cut for.

    A recording that yields no clip at all is a recording nothing was published
    from, which is a failure rather than a page of posters: every demo would
    have lost its video for the same reason, and that reason is worth a red run.
    """
    clips = {}
    for demo in demos:
        clip = cut(
            recorder, recording, media, demo.slug, demo.bounds(recording.duration)
        )
        if clip is not None:
            clips[demo.slug] = clip
    if demos and not clips:
        raise GenerationError(
            f"No demo could be cut out of {recording.path.name}, so there is "
            "nothing for the website to play"
        )
    return clips


def copy_poster(demo: Demo, artifacts: Path, media: Path) -> str | None:
    """The demo's final screenshot, which stands in for the clip that may not exist."""
    for name in reversed(demo.screenshots):
        source = artifacts / name
        if not source.is_file():
            continue
        shutil.copy(source, media / f"{demo.slug}.png")
        return f"{MEDIA_DIRECTORY}/{demo.slug}.png"
    return None


def write(
    output: Path,
    artifacts: Path,
    recording: Recording | None,
    demos: Sequence[Demo],
    recorder: Path | None,
) -> None:
    media = output / MEDIA_DIRECTORY
    # The manifest names everything the website serves, so a second run into
    # the same output must leave nothing of the first behind: a renamed or
    # deleted demo's clip would otherwise stay there to be published, and a
    # manifest that outlived the media it names would be published against it.
    (output / MANIFEST_NAME).unlink(missing_ok=True)
    shutil.rmtree(media, ignore_errors=True)
    media.mkdir(parents=True, exist_ok=True)
    clips: dict[str, Clip] = {}
    if recording is not None and recorder is not None:
        clips = cut_clips(recorder, recording, demos, media)
    manifest = {
        "demos": [
            demo.as_json(copy_poster(demo, artifacts, media), clips.get(demo.slug))
            for demo in sorted(demos, key=lambda demo: demo.slug)
        ]
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
    named = os.environ.get(RECORDER_ENV)
    parser.add_argument(
        "--recorder",
        type=Path,
        default=Path(named) if named else None,
        help=f"The recorder that cuts each demo's clip; defaults to ${RECORDER_ENV}",
    )
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
        recording = read_recording(trace)
        demos = read_demos(events, origin_of(events, recording))
        issues = problems(demos)
        if issues:
            for issue in issues:
                print(issue, file=sys.stderr)
            print(f"Not documenting {trace.name}", file=sys.stderr)
            return 1
        if recording is not None and arguments.recorder is None:
            raise GenerationError(
                f"--recorder, or ${RECORDER_ENV}, must name the recorder that cuts "
                f"each demo's clip out of {recording.path.name}"
            )
        write(
            arguments.output,
            arguments.artifacts_dir,
            recording,
            demos,
            arguments.recorder,
        )
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
