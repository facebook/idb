# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Generate documentation from fixture traces, without a simulator or a run."""

from __future__ import annotations

import io
import json
import os
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

PREFIX = "idb-e2e-fixture"
ORIGIN = 1000.0
# The prefix a build that imports the suite by its path in the repository adds
# to the test names it records.
PATH_PREFIX = "fbobjc.Tools.idb.Source."
POLLED = ["idb", "ui", "describe-all", "--json"]
PUBLISHED = ["idb", "open", "https://example.com"]

NO_OUTPUT: dict[str, Any] = {"bytes": 0, "text": "", "truncated": False}
OPENED: dict[str, Any] = {"bytes": 7, "text": "opened\n", "truncated": False}


def trace_events(
    *,
    slug: str = SLUG,
    test: str = TEST,
    status: str = "passed",
    steps: Sequence[str] = ("Open a URL on the simulator",),
    screenshots: Sequence[str] = (),
) -> list[dict[str, Any]]:
    """One documented test's worth of trace, with the polling it really does."""
    recorded: list[dict[str, Any]] = [
        {"time": ORIGIN, "event": "recording_started", "test": ""},
        {"time": ORIGIN + 1, "event": "test_started", "test": test},
        {
            "time": ORIGIN + 2,
            "event": "demo",
            "test": test,
            "slug": slug,
            "title": "Open a URL on a simulator",
            "summary": "Hand a URL to the simulator and let it pick the app.",
        },
        {"time": ORIGIN + 3, "event": "command_started", "test": test, "argv": POLLED},
        {
            "time": ORIGIN + 4,
            "event": "command_finished",
            "test": test,
            "argv": POLLED,
            "returncode": 0,
            "seconds": 1.0,
        },
    ]
    at = ORIGIN + 5
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
        for prefix, events in (traces or {PREFIX: trace_events()}).items():
            (source / f"{prefix}-commands.jsonl").write_text(
                "".join(json.dumps(event) + "\n" for event in events)
            )
        if video is not None:
            # The recorder writes its report at the recording's own path with
            # .json appended, whichever container it wrote.
            (source / f"{PREFIX}{container}").write_bytes(b"a recording")
            (source / f"{PREFIX}{container}.json").write_text(json.dumps(video))
        for name in screenshots:
            (source / name).write_bytes(b"a screenshot")
        yield source, output


def generate(source: Path, output: Path, table: dict[str, str] | None = None) -> int:
    with mock.patch.dict(
        generate_documentation.DOCUMENTED_DEMOS, table or TABLE, clear=True
    ):
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return main(["--artifacts-dir", str(source), "--output", str(output)])


def refused(source: Path, output: Path, table: dict[str, str] | None = None) -> str:
    """The reasons the generator gave for publishing nothing."""
    with mock.patch.dict(
        generate_documentation.DOCUMENTED_DEMOS, table or TABLE, clear=True
    ):
        errors = io.StringIO()
        with redirect_stdout(io.StringIO()), redirect_stderr(errors):
            status = main(["--artifacts-dir", str(source), "--output", str(output)])
    assert status == 1, f"expected the generator to refuse, it returned {status}"
    return errors.getvalue()


def manifest(output: Path) -> dict[str, Any]:
    return json.loads((output / MANIFEST_NAME).read_text())


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

    def test_measures_offsets_from_the_first_recorded_frame(self) -> None:
        with artifacts() as (source, output):
            generate(source, output)
            demo = manifest(output)["demos"][0]

        self.assertEqual((demo["start"], demo["end"]), (2.0, 6.0))

    def test_sorts_demos_by_slug(self) -> None:
        table = {SLUG: TEST, OTHER_SLUG: OTHER_TEST}
        events = trace_events(slug=OTHER_SLUG, test=OTHER_TEST) + trace_events()
        with artifacts({PREFIX: events}) as (source, output):
            self.assertEqual(generate(source, output, table), 0)
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
        with artifacts() as (source, output):
            generate(source, output / "first")
            generate(source, output / "second")
            first = (output / "first" / MANIFEST_NAME).read_bytes()
            second = (output / "second" / MANIFEST_NAME).read_bytes()

        self.assertEqual(first, second)


class VideoTests(unittest.TestCase):
    def test_publishes_a_recording_browsers_can_play(self) -> None:
        report = {"encoding": "h264", "width": 590, "height": 1278, "duration": 42.5}
        with artifacts(video=report) as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)["video"]
            copied = (output / "media" / f"{PREFIX}.mp4").read_bytes()

        self.assertEqual(
            published,
            {
                "source": f"media/{PREFIX}.mp4",
                "type": "video/mp4",
                "width": 590,
                "height": 1278,
                "duration": 42.5,
            },
        )
        self.assertEqual(copied, b"a recording")

    def test_documents_the_transcript_without_a_recording_browsers_reject(self) -> None:
        report = {"encoding": "mjpeg", "width": 590, "height": 1278, "duration": 42.5}
        with artifacts(video=report, container=".mov") as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)
            copied = (output / "media" / f"{PREFIX}.mov").exists()

        self.assertIsNone(published["video"])
        self.assertEqual(len(published["demos"]), 1)
        self.assertFalse(copied)

    def test_refuses_to_serve_a_recording_as_a_type_browsers_reject(self) -> None:
        report = {"encoding": "h264", "width": 590, "height": 1278, "duration": 42.5}
        with artifacts(video=report, container=".mov") as (source, output):
            errors = self.errors(source, output)
            published = manifest(output)

        self.assertIsNone(published["video"])
        self.assertIn("video/quicktime container", errors)

    def test_keeps_an_offset_the_recording_does_not_reach_inside_it(self) -> None:
        report = {"encoding": "h264", "width": 590, "height": 1278, "duration": 3.0}
        with artifacts(video=report) as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertEqual((demo["start"], demo["end"]), (2.0, 3.0))
        self.assertEqual(demo["commands"][0]["start"], 3.0)

    def test_leaves_offsets_alone_when_there_is_nothing_to_seek(self) -> None:
        with artifacts() as (source, output):
            self.assertEqual(generate(source, output), 0)
            demo = manifest(output)["demos"][0]

        self.assertEqual((demo["start"], demo["end"]), (2.0, 6.0))
        self.assertEqual(demo["commands"][0]["start"], 4.5)

    def test_documents_the_transcript_when_nothing_was_recorded(self) -> None:
        with artifacts() as (source, output):
            self.assertEqual(generate(source, output), 0)
            published = manifest(output)

        self.assertIsNone(published["video"])
        self.assertEqual(len(published["demos"]), 1)

    def test_documents_the_transcript_when_the_report_cannot_be_read(self) -> None:
        report = {"encoding": "h264", "width": 590, "height": 1278, "duration": 42.5}
        with artifacts(video=report) as (source, output):
            (source / f"{PREFIX}.mp4.json").write_text('{"encoding": "h264"')
            errors = self.errors(source, output)
            published = manifest(output)

        self.assertIsNone(published["video"])
        self.assertEqual(len(published["demos"]), 1)
        self.assertIn("does not describe a recording", errors)

    def test_documents_the_transcript_when_the_report_lost_a_dimension(self) -> None:
        with artifacts(video={"encoding": "h264", "width": 590, "duration": 1.0}) as (
            source,
            output,
        ):
            errors = self.errors(source, output)
            published = manifest(output)

        self.assertIsNone(published["video"])
        self.assertIn("does not describe a recording", errors)

    def test_says_which_encoding_it_would_not_publish(self) -> None:
        report = {"encoding": "mjpeg", "width": 590, "height": 1278, "duration": 1.0}
        with artifacts(video=report, container=".mov") as (source, output):
            errors = self.errors(source, output)

        self.assertIn("mjpeg", errors)
        self.assertIn("IDB_E2E_RECORDER_ENCODING=h264", errors)

    def errors(self, source: Path, output: Path) -> str:
        """What the generator said while publishing everything else."""
        with mock.patch.dict(
            generate_documentation.DOCUMENTED_DEMOS, TABLE, clear=True
        ):
            errors = io.StringIO()
            with redirect_stdout(io.StringIO()), redirect_stderr(errors):
                status = main(["--artifacts-dir", str(source), "--output", str(output)])

        self.assertEqual(status, 0)
        return errors.getvalue()


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
        table = {SLUG: TEST, OTHER_SLUG: OTHER_TEST}
        with artifacts() as (source, output):
            reasons = refused(source, output, table)
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
        table = {SLUG: TEST, OTHER_SLUG: OTHER_TEST}
        unfinished = [
            event for event in trace_events() if event["event"] != "test_finished"
        ]
        events = unfinished + trace_events(slug=OTHER_SLUG, test=OTHER_TEST)
        with artifacts({PREFIX: events}) as (source, output):
            reasons = refused(source, output, table)
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
        table = {SLUG: TEST, OTHER_SLUG: OTHER_TEST}
        traces = {
            f"{PREFIX}-one": trace_events(),
            f"{PREFIX}-two": trace_events(slug=OTHER_SLUG, test=OTHER_TEST),
        }
        with artifacts(traces) as (source, output):
            reasons = refused(source, output, table)
            self.assert_publishes_nothing(output)

        self.assertIn("More than one command trace recorded demos", reasons)
