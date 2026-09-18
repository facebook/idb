# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Generate documentation from fixture traces, without a simulator or a run."""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import contextmanager, redirect_stderr, redirect_stdout
from pathlib import Path
from typing import Any, Iterator, Sequence
from unittest import mock

from . import generate_documentation
from .generate_documentation import main, MANIFEST_NAME

SLUG = "open-a-url"
TEST = "EndToEndTests.test_system.OpenUrlTests.test_opening_a_url"
OTHER_SLUG = "tap-by-accessibility-id"
OTHER_TEST = "EndToEndTests.test_accessibility.AccessibilityTests.test_ui_tap"
TABLE = {SLUG: TEST}
BOTH = {SLUG: TEST, OTHER_SLUG: OTHER_TEST}

PREFIX = "idb-e2e-fixture"
ORIGIN = 1000.0
# The prefix a build that imports the suite by its path in the repository adds
# to the test names it records.
PATH_PREFIX = "fbobjc.Tools.idb.Source."
POLLED = ["idb", "ui", "describe-all", "--json"]
PUBLISHED = ["idb", "open", "https://example.com"]

NO_OUTPUT: dict[str, Any] = {"bytes": 0, "text": "", "truncated": False}
OPENED: dict[str, Any] = {"bytes": 7, "text": "opened\n", "truncated": False}

RECORDING = "a recording"

# Stands in for `sim-video clip`, which needs a Mac and a real recording. It
# cuts the fixture the way the recorder cuts video -- writing what interval it
# was asked for, and a report of the clip beside it -- so a clip's content and
# duration are both checkable without decoding anything. The environment tells
# it which clips to fail, so the generator's degradation can be driven from a
# test without a second stub.
RECORDER_STUB = '''
"""Cut a fixture recording the way `sim-video clip` cuts a real one."""

import argparse
import json
import os
import pathlib
import sys

parser = argparse.ArgumentParser()
parser.add_argument("command")
parser.add_argument("--start", type=float, required=True)
parser.add_argument("--end", type=float, required=True)
parser.add_argument("input")
parser.add_argument("output")
arguments = parser.parse_args()

if arguments.command != "clip":
    sys.exit(f"{arguments.command} is not a subcommand this stub has")
output = pathlib.Path(arguments.output)
if output.stem in os.environ.get("STUB_REFUSES", "").split(","):
    sys.exit(f"{output.stem} is a clip this recorder cannot cut")
if output.exists():
    sys.exit(f"Output already exists: {output}")

recording = pathlib.Path(arguments.input).read_text()
output.write_text(f"{recording} from {arguments.start} to {arguments.end}")
report = {
    "encoding": "h264",
    "width": 590,
    "height": 1278,
    "duration": arguments.end - arguments.start,
}
if output.stem in os.environ.get("STUB_MISREPORTS", "").split(","):
    del report["duration"]
pathlib.Path(f"{output}.json").write_text(json.dumps(report))
'''


def report(**overrides: Any) -> dict[str, Any]:
    """The report the recorder writes beside a recording it finished."""
    described = {"encoding": "h264", "width": 590, "height": 1278, "duration": 42.5}
    described.update(overrides)
    return described


def trace_events(
    *,
    slug: str = SLUG,
    test: str = TEST,
    status: str = "passed",
    steps: Sequence[str] = ("Open a URL on the simulator",),
    screenshots: Sequence[str] = (),
    shift: float = 0.0,
    setup: float = 1.0,
    commands_after: float = 3.0,
) -> list[dict[str, Any]]:
    """One documented test's worth of trace, with the polling it really does.

    `shift` moves the whole test later, so two of these make one run of two
    tests; `setup` is how long the test spent before the demo was marked, and
    `commands_after` how long it spent after that before the first command the
    demo publishes -- which is where the clip's lead is taken from.
    """
    started = ORIGIN + 1 + shift
    began = started + setup
    recorded: list[dict[str, Any]] = [
        {"time": ORIGIN + shift, "event": "recording_started", "test": ""},
        {"time": started, "event": "test_started", "test": test},
        {
            "time": began,
            "event": "demo",
            "test": test,
            "slug": slug,
            "title": "Open a URL on a simulator",
            "summary": "Hand a URL to the simulator and let it pick the app.",
        },
        {"time": began + 1, "event": "command_started", "test": test, "argv": POLLED},
        {
            "time": began + 2,
            "event": "command_finished",
            "test": test,
            "argv": POLLED,
            "returncode": 0,
            "seconds": 1.0,
        },
    ]
    at = began + commands_after
    for index, step in enumerate(steps):
        recorded.append(
            {
                "time": at + index,
                "event": "command_finished",
                "test": test,
                "argv": PUBLISHED,
                "returncode": 0,
                "seconds": 0.5,
                "step": step,
                "stdout": OPENED,
                "stderr": NO_OUTPUT,
            }
        )
    at += len(steps)
    for index, name in enumerate(screenshots):
        recorded.append(
            {"time": at + index, "event": "screenshot", "test": test, "path": name}
        )
    at += len(screenshots)
    recorded.append(
        {"time": at, "event": "test_finished", "test": test, "status": status}
    )
    return recorded


def two_tests(*, shift: float = 10.0, steps: int = 2) -> list[dict[str, Any]]:
    """A run of the two documented tests, the second beginning after the first."""
    return trace_events() + trace_events(
        slug=OTHER_SLUG,
        test=OTHER_TEST,
        shift=shift,
        steps=tuple(f"Step {index}" for index in range(steps)),
    )


@contextmanager
def artifacts(
    traces: dict[str, list[dict[str, Any]]] | None = None,
    *,
    video: dict[str, Any] | None = None,
    container: str = ".mp4",
    screenshots: Sequence[str] = (),
) -> Iterator[tuple[Path, Path]]:
    """An artifacts directory beside an output directory, as a run leaves them."""
    with tempfile.TemporaryDirectory() as root:
        directory = Path(root)
        source, output = directory / "artifacts", directory / "output"
        source.mkdir()
        # Run by the interpreter running the tests, so the stub needs nothing
        # of the machine beyond what is already executing it.
        stub = recorder(source)
        stub.write_text(f"#!{sys.executable}{RECORDER_STUB}")
        stub.chmod(0o755)
        for prefix, events in (traces or {PREFIX: trace_events()}).items():
            (source / f"{prefix}-commands.jsonl").write_text(
                "".join(json.dumps(event) + "\n" for event in events)
            )
        if video is not None:
            # The recorder writes its report at the recording's own path with
            # .json appended, whichever container it wrote.
            (source / f"{PREFIX}{container}").write_text(RECORDING)
            (source / f"{PREFIX}{container}.json").write_text(json.dumps(video))
        for name in screenshots:
            (source / name).write_bytes(b"a screenshot")
        yield source, output


def recorder(source: Path) -> Path:
    """The stub recorder that stands beside a fixture run's artifacts."""
    return source.parent / "sim-video"


def documented(
    source: Path,
    output: Path,
    table: dict[str, str] | None = None,
    *,
    cut_with: Path | None = None,
) -> tuple[int, str]:
    """Generate documentation, and whatever the generator said while doing it."""
    argv = ["--artifacts-dir", str(source), "--output", str(output)]
    if cut_with is not None:
        argv += ["--recorder", str(cut_with)]
    with mock.patch.dict(
        generate_documentation.DOCUMENTED_DEMOS, table or TABLE, clear=True
    ):
        errors = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(errors):
            return main(argv), errors.getvalue()


def generate(source: Path, output: Path, table: dict[str, str] | None = None) -> int:
    status, _ = documented(source, output, table, cut_with=recorder(source))
    return status


def warnings(source: Path, output: Path, table: dict[str, str] | None = None) -> str:
    """What the generator said while publishing everything it could."""
    status, errors = documented(source, output, table, cut_with=recorder(source))
    assert status == 0, f"expected the generator to publish, it returned {status}"
    return errors


def refused(source: Path, output: Path, table: dict[str, str] | None = None) -> str:
    """The reasons the generator gave for publishing nothing."""
    status, errors = documented(source, output, table, cut_with=recorder(source))
    assert status == 1, f"expected the generator to refuse, it returned {status}"
    return errors


def manifest(output: Path) -> dict[str, Any]:
    return json.loads((output / MANIFEST_NAME).read_text())


def demos(output: Path) -> dict[str, dict[str, Any]]:
    return {demo["slug"]: demo for demo in manifest(output)["demos"]}


def clip_of(output: Path, slug: str = SLUG) -> str:
    """The interval of the recording a demo's clip was cut from."""
    return (output / "media" / f"{slug}.mp4").read_text()


class PublishedDemoTests(unittest.TestCase):
    def test_publishes_what_the_demo_declared(self) -> None:
        with artifacts() as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertEqual(
            {key: demo[key] for key in ("slug", "title", "summary", "test")},
            {
                "slug": SLUG,
                "title": "Open a URL on a simulator",
                "summary": "Hand a URL to the simulator and let it pick the app.",
                "test": TEST,
            },
        )

    def test_publishes_only_the_commands_the_demo_named(self) -> None:
        with artifacts() as (source, output):
            generate(source, output)
            commands = manifest(output)["demos"][0]["commands"]

        self.assertEqual(
            commands,
            [
                {
                    "step": "Open a URL on the simulator",
                    "argv": PUBLISHED,
                    "returncode": 0,
                    "start": 4.5,
                    "seconds": 0.5,
                    "stdout": OPENED,
                    "stderr": NO_OUTPUT,
                }
            ],
        )

    def test_sorts_demos_by_slug(self) -> None:
        events = trace_events(slug=OTHER_SLUG, test=OTHER_TEST) + trace_events()
        with artifacts({PREFIX: events}) as (source, output):
            self.assertEqual(generate(source, output, BOTH), 0)
            published = [demo["slug"] for demo in manifest(output)["demos"]]

        self.assertEqual(published, [SLUG, OTHER_SLUG])

    def test_publishes_a_run_that_named_its_tests_by_repository_path(self) -> None:
        events = trace_events(test=f"{PATH_PREFIX}{TEST}")
        with artifacts({PREFIX: events}) as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertEqual(demo["test"], TEST)
        self.assertEqual(len(demo["commands"]), 1)

    def test_writes_the_same_bytes_for_the_same_run(self) -> None:
        with artifacts(video=report()) as (source, output):
            generate(source, output / "first")
            generate(source, output / "second")
            first = (output / "first" / MANIFEST_NAME).read_bytes()
            second = (output / "second" / MANIFEST_NAME).read_bytes()

        self.assertEqual(first, second)


class OriginTests(unittest.TestCase):
    """Where the recording's own time zero is, which every offset is measured from."""

    def test_measures_offsets_from_the_frame_the_recorder_reports(self) -> None:
        with artifacts(video=report(startedAt=ORIGIN + 0.5)) as (source, output):
            self.assertEqual(generate(source, output), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 3.0 to 6.5")

    def test_falls_back_to_the_event_when_the_recorder_reports_no_frame(self) -> None:
        with artifacts(video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 3.5 to 7.0")


class ClipTests(unittest.TestCase):
    def test_publishes_a_clip_of_the_demo_alone(self) -> None:
        with artifacts(video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)["demos"][0]["video"]

        self.assertEqual(
            published,
            {
                "source": f"media/{SLUG}.mp4",
                "type": "video/mp4",
                "width": 590,
                "height": 1278,
                "duration": 3.5,
            },
        )

    def test_cuts_each_demo_the_interval_it_was_performed_in(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report()) as (source, output):
            self.assertEqual(generate(source, output, BOTH), 0)
            published = demos(output)
            cut = (clip_of(output, SLUG), clip_of(output, OTHER_SLUG))

        self.assertEqual(
            cut,
            (f"{RECORDING} from 3.5 to 7.0", f"{RECORDING} from 13.5 to 18.0"),
        )
        self.assertEqual(published[SLUG]["video"]["duration"], 3.5)
        self.assertEqual(published[OTHER_SLUG]["video"]["duration"], 4.5)

    def test_seeks_commands_inside_the_clip_rather_than_the_recording(self) -> None:
        with artifacts(video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertEqual(demo["commands"][0]["start"], 1.0)

    def test_publishes_a_demo_with_no_interval_to_seek_to(self) -> None:
        with artifacts(video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertNotIn("start", demo)
        self.assertNotIn("end", demo)
        self.assertEqual(demo["video"]["duration"], 3.5)

    def test_keeps_a_clip_out_of_the_test_that_ran_before_it(self) -> None:
        # A demo whose first command runs a quarter of a second after its test
        # began: a second of lead would reach into the test before it.
        events = trace_events(setup=0.25, commands_after=0.5)
        with artifacts({PREFIX: events}, video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 1.0 to 3.75")

    def test_cuts_from_the_first_command_rather_than_the_test_s_setup(self) -> None:
        # A demo is marked where its test begins, and this test then spends ten
        # seconds terminating apps, launching one and waiting for it to answer.
        # None of that is what the demo is about.
        events = trace_events(setup=0.0, commands_after=10.0)
        with artifacts({PREFIX: events}, video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 9.5 to 13.0")

    def test_keeps_a_clip_out_of_the_test_that_ran_next(self) -> None:
        with artifacts({PREFIX: two_tests(shift=5.5)}, video=report()) as (
            source,
            output,
        ):
            self.assertEqual(generate(source, output, BOTH), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 3.5 to 6.5")

    def test_begins_a_clip_where_the_recording_does(self) -> None:
        # The recorder's first frame lands after the demo's first command, so a
        # second of lead would begin before the recording has any frames.
        with artifacts(video=report(startedAt=ORIGIN + 4.0)) as (source, output):
            self.assertEqual(generate(source, output), 0)

            self.assertEqual(clip_of(output), f"{RECORDING} from 0.0 to 3.0")

    def test_ends_a_clip_where_the_recording_does(self) -> None:
        with artifacts(video=report(duration=5.0)) as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]
            cut = clip_of(output)

        self.assertEqual(cut, f"{RECORDING} from 3.5 to 5.0")
        self.assertEqual(demo["video"]["duration"], 1.5)
        self.assertEqual(demo["commands"][0]["start"], 1.0)

    def test_serves_nothing_of_the_run_the_manifest_does_not_name(self) -> None:
        with artifacts(video=report()) as (source, output):
            self.assertEqual(generate(source, output), 0)
            served = sorted(path.name for path in (output / "media").iterdir())

        self.assertEqual(served, [f"{SLUG}.mp4"])

    def test_cuts_with_the_recorder_the_environment_names(self) -> None:
        with artifacts(video=report()) as (source, output):
            with mock.patch.dict(
                os.environ, {"IDB_E2E_RECORDER_PATH": str(recorder(source))}
            ):
                status, _ = documented(source, output)

            self.assertEqual(status, 0)
            self.assertEqual(clip_of(output), f"{RECORDING} from 3.5 to 7.0")


class DegradationTests(unittest.TestCase):
    """What a demo publishes when its clip cannot be cut."""

    def test_documents_a_demo_whose_clip_the_recorder_refused(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report()) as (source, output):
            with mock.patch.dict(os.environ, {"STUB_REFUSES": SLUG}):
                said = warnings(source, output, BOTH)
            published = demos(output)

        self.assertIsNone(published[SLUG]["video"])
        self.assertEqual(published[OTHER_SLUG]["video"]["duration"], 4.5)
        self.assertIn(f"Could not cut {SLUG} out of {PREFIX}.mp4", said)
        self.assertIn(f"{SLUG} is a clip this recorder cannot cut", said)

    def test_documents_a_demo_whose_clip_was_not_described(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report()) as (source, output):
            with mock.patch.dict(os.environ, {"STUB_MISREPORTS": SLUG}):
                said = warnings(source, output, BOTH)
            published = demos(output)
            served = sorted(path.name for path in (output / "media").iterdir())

        self.assertIsNone(published[SLUG]["video"])
        self.assertIn("does not describe a clip", said)
        self.assertEqual(served, [f"{OTHER_SLUG}.mp4"])

    def test_documents_a_demo_the_recording_is_too_short_for(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report(duration=11.3)) as (
            source,
            output,
        ):
            said = warnings(source, output, BOTH)
            published = demos(output)

        self.assertEqual(published[SLUG]["video"]["duration"], 3.5)
        self.assertIsNone(published[OTHER_SLUG]["video"])
        self.assertIn("too little to publish as a clip", said)

    def test_refuses_a_run_no_demo_could_be_cut_out_of(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report()) as (source, output):
            with mock.patch.dict(os.environ, {"STUB_REFUSES": f"{SLUG},{OTHER_SLUG}"}):
                reasons = refused(source, output, BOTH)

            self.assertFalse((output / MANIFEST_NAME).exists())

        self.assertIn(f"No demo could be cut out of {PREFIX}.mp4", reasons)

    def test_refuses_a_run_with_no_recorder_to_cut_with(self) -> None:
        with artifacts(video=report()) as (source, output):
            with mock.patch.dict(os.environ, {}, clear=True):
                status, reasons = documented(source, output)

            self.assertEqual(status, 1)
            self.assertFalse((output / MANIFEST_NAME).exists())

        self.assertIn("IDB_E2E_RECORDER_PATH", reasons)

    def test_forgets_the_manifest_of_the_run_it_documented_before(self) -> None:
        with artifacts({PREFIX: two_tests()}, video=report()) as (source, output):
            self.assertEqual(generate(source, output, BOTH), 0)

            with mock.patch.dict(os.environ, {"STUB_REFUSES": f"{SLUG},{OTHER_SLUG}"}):
                refused(source, output, BOTH)

            self.assertFalse((output / MANIFEST_NAME).exists())


class RecordingTests(unittest.TestCase):
    def test_documents_the_transcript_without_a_recording_browsers_reject(self) -> None:
        described = report(encoding="mjpeg")
        with artifacts(video=described, container=".mov") as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)
            copied = (output / "media" / f"{PREFIX}.mov").exists()

        self.assertIsNone(published["demos"][0]["video"])
        self.assertEqual(len(published["demos"]), 1)
        self.assertFalse(copied)

    def test_refuses_to_serve_a_recording_as_a_type_browsers_reject(self) -> None:
        with artifacts(video=report(), container=".mov") as (source, output):
            said = warnings(source, output)
            published = manifest(output)

        self.assertIsNone(published["demos"][0]["video"])
        self.assertIn("video/quicktime container", said)

    def test_documents_the_transcript_when_nothing_was_recorded(self) -> None:
        with artifacts() as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)

        self.assertIsNone(published["demos"][0]["video"])
        self.assertEqual(len(published["demos"]), 1)

    def test_documents_the_transcript_when_the_report_cannot_be_read(self) -> None:
        with artifacts(video=report()) as (source, output):
            (source / f"{PREFIX}.mp4.json").write_text('{"encoding": "h264"')
            said = warnings(source, output)
            published = manifest(output)

        self.assertIsNone(published["demos"][0]["video"])
        self.assertEqual(len(published["demos"]), 1)
        self.assertIn("does not describe a recording", said)

    def test_documents_the_transcript_when_the_report_lost_the_duration(self) -> None:
        described = report()
        del described["duration"]
        with artifacts(video=described) as (source, output):
            said = warnings(source, output)
            published = manifest(output)

        self.assertIsNone(published["demos"][0]["video"])
        self.assertIn("does not describe a recording", said)

    def test_says_which_encoding_it_would_not_publish(self) -> None:
        described = report(encoding="mjpeg", duration=1.0)
        with artifacts(video=described, container=".mov") as (source, output):
            said = warnings(source, output)

        self.assertIn("mjpeg", said)
        self.assertIn("IDB_E2E_RECORDER_ENCODING=h264", said)


class PosterTests(unittest.TestCase):
    def test_uses_the_demo_s_last_screenshot(self) -> None:
        names = [f"{PREFIX}-screenshot-1.png", f"{PREFIX}-screenshot-2.png"]
        with artifacts(
            {PREFIX: trace_events(screenshots=names)}, screenshots=names
        ) as (source, output):
            generate(source, output)
            poster = manifest(output)["demos"][0]["poster"]
            copied = (output / "media" / f"{SLUG}.png").read_bytes()

        self.assertEqual(poster, f"media/{SLUG}.png")
        self.assertEqual(copied, b"a screenshot")

    def test_has_no_poster_when_the_screenshot_was_never_written(self) -> None:
        name = f"{PREFIX}-screenshot-1.png"
        with artifacts({PREFIX: trace_events(screenshots=[name])}) as (source, output):
            generate(source, output)

            self.assertIsNone(manifest(output)["demos"][0]["poster"])

    def test_forgets_the_media_of_the_run_it_documented_before(self) -> None:
        name = f"{PREFIX}-screenshot-1.png"
        with artifacts(
            {PREFIX: trace_events(screenshots=[name])}, screenshots=[name]
        ) as (source, output):
            generate(source, output)
            poster = output / "media" / f"{SLUG}.png"
            self.assertTrue(poster.is_file())

            (source / name).unlink()
            self.assertEqual(generate(source, output), 0)

            self.assertIsNone(manifest(output)["demos"][0]["poster"])
            self.assertFalse(poster.exists())


class RefusalTests(unittest.TestCase):
    def assert_publishes_nothing(self, output: Path) -> None:
        self.assertFalse((output / MANIFEST_NAME).exists())

    def test_refuses_a_demo_whose_test_did_not_pass(self) -> None:
        with artifacts({PREFIX: trace_events(status="failed")}) as (source, output):
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn(f"{SLUG} finished failed", reasons)

    def test_refuses_a_demo_the_run_never_performed(self) -> None:
        with artifacts() as (source, output):
            reasons = refused(source, output, BOTH)
            self.assert_publishes_nothing(output)

        self.assertIn(f"{OTHER_SLUG} was not performed by this run", reasons)

    def test_refuses_a_demo_the_website_does_not_publish(self) -> None:
        with artifacts() as (source, output):
            reasons = refused(source, output, {OTHER_SLUG: OTHER_TEST})
            self.assert_publishes_nothing(output)

        self.assertIn(f"{SLUG} is not a demo the website publishes", reasons)

    def test_refuses_a_demo_another_test_performed(self) -> None:
        with artifacts() as (source, output):
            reasons = refused(source, output, {SLUG: OTHER_TEST})
            self.assert_publishes_nothing(output)

        self.assertIn(f"{SLUG} is published as {OTHER_TEST}", reasons)

    def test_refuses_a_demo_that_named_no_commands(self) -> None:
        with artifacts({PREFIX: trace_events(steps=())}) as (source, output):
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn(f"{SLUG} named no commands to publish", reasons)

    def test_refuses_a_demo_performed_twice(self) -> None:
        with artifacts({PREFIX: trace_events() + trace_events()}) as (source, output):
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn(f"{SLUG} was performed more than once", reasons)

    def test_says_a_demo_was_performed_more_than_once_only_once(self) -> None:
        with artifacts({PREFIX: trace_events() * 3}) as (source, output):
            reasons = refused(source, output)

        self.assertEqual(reasons.count(f"{SLUG} was performed more than once"), 1)

    def test_refuses_a_demo_that_begins_inside_another(self) -> None:
        unfinished = [
            event for event in trace_events() if event["event"] != "test_finished"
        ]
        events = unfinished + trace_events(slug=OTHER_SLUG, test=OTHER_TEST)
        with artifacts({PREFIX: events}) as (source, output):
            reasons = refused(source, output, BOTH)
            self.assert_publishes_nothing(output)

        self.assertIn(
            f"{SLUG} is still being performed where {OTHER_SLUG} begins", reasons
        )

    def test_refuses_a_run_holding_a_trace_it_cannot_read(self) -> None:
        with artifacts() as (source, output):
            (source / f"{PREFIX}-other-commands.jsonl").write_text("{not json}\n")
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn(
            f"{PREFIX}-other-commands.jsonl line 1 is not a trace event", reasons
        )

    def test_refuses_a_trace_line_that_names_no_event(self) -> None:
        with artifacts() as (source, output):
            (source / f"{PREFIX}-other-commands.jsonl").write_text("[1, 2]\n")
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn(f"{PREFIX}-other-commands.jsonl line 1 names no event", reasons)

    def test_refuses_a_run_that_documented_nothing(self) -> None:
        events = [event for event in trace_events() if event["event"] != "demo"]
        with artifacts({PREFIX: events}) as (source, output):
            reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn("recorded a demo", reasons)

    def test_refuses_to_document_the_read_only_client(self) -> None:
        with artifacts() as (source, output):
            with mock.patch.dict(os.environ, {"IDB_E2E_READ_ONLY_CLIENT": "1"}):
                reasons = refused(source, output)
            self.assert_publishes_nothing(output)

        self.assertIn("IDB_E2E_READ_ONLY_CLIENT=1", reasons)

    def test_refuses_a_run_whose_demos_are_split_across_traces(self) -> None:
        traces = {
            f"{PREFIX}-one": trace_events(),
            f"{PREFIX}-two": trace_events(slug=OTHER_SLUG, test=OTHER_TEST),
        }
        with artifacts(traces) as (source, output):
            reasons = refused(source, output, BOTH)
            self.assert_publishes_nothing(output)

        self.assertIn("More than one command trace recorded demos", reasons)
