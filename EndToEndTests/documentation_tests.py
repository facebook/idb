# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test the demo contract, output normalisation and capture without a simulator.

The *_tests.py name excludes this module from e2e unittest discovery, which
uses test*.py. Run it separately with
python -m unittest EndToEndTests.documentation_tests.
"""

from __future__ import annotations

import importlib
import io
import json
import os
import tempfile
import types
import unittest
from contextlib import contextmanager
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Iterator
from unittest import mock

from . import documentation, harness, recording as recording_module
from .documentation import (
    ARTIFACTS_PLACEHOLDER,
    capture,
    Demo,
    demo_for,
    documented_demo,
    HOME_PLACEHOLDER,
    MAXIMUM_CAPTURED_CHARACTERS,
    normalisation_rules,
    normalise,
    Rule,
    TEMPORARY_PLACEHOLDER,
    test_identity,
    Transcript,
    UDID_PLACEHOLDER,
    UUID_PLACEHOLDER,
)
from .harness import Completed, IdbEndToEndTestCase
from .recording import CONTAINERS, ENCODING_ENV, Recording

UDID = "11111111-2222-3333-4444-555555555555"
OTHER_UUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
DEVICE_SET = Path("/tmp/device-set")
WORKING_DIRECTORY = Path("/tmp/idb-e2e-4xdxnimi")
ARTIFACTS = Path("/tmp/idb-e2e-4xdxnimi/artifacts")
HOME = Path("/Users/somebody")
TEMPORARY_DIRECTORY = Path("/tmp")
# The prefix a build that imports these modules by repository path adds.
PATH_PREFIX = "fbobjc.Tools.idb.Source."

# An unpaired surrogate half, which no UTF-8 decoder accepts.
BINARY_OUTPUT = b"\x89PNG\r\n\x1a\n\xed\xa0\x80"


def rules() -> tuple[Rule, ...]:
    return normalisation_rules(
        UDID,
        DEVICE_SET,
        WORKING_DIRECTORY,
        artifacts=ARTIFACTS,
        home=HOME,
        temporary_directory=TEMPORARY_DIRECTORY,
    )


def declare(slug: str, published: str | None) -> Demo | None:
    """Declare a demo against a published table holding only the given entry."""
    table = {} if published is None else {slug: published}
    with mock.patch.dict(documentation.DOCUMENTED_DEMOS, table, clear=True):

        class Declaring(unittest.TestCase):
            @documented_demo(slug=slug, title="Title", summary="A summary")
            def test_declaring(self) -> None: ...

    return demo_for(Declaring("test_declaring"))


PUBLISHED_TEST = test_identity(f"{__name__}.declare.<locals>.Declaring.test_declaring")


class DemoContractTests(unittest.TestCase):
    def test_accepts_the_test_the_table_publishes(self) -> None:
        demo = declare("tap-here", PUBLISHED_TEST)

        assert demo is not None
        self.assertEqual(demo.slug, "tap-here")

    def test_rejects_a_demo_the_website_does_not_publish(self) -> None:
        with self.assertRaisesRegex(ValueError, "does not publish"):
            declare("tap-here", None)

    def test_rejects_a_demo_published_under_another_test(self) -> None:
        with self.assertRaisesRegex(ValueError, "but declared by"):
            declare("tap-here", "EndToEndTests.test_renamed.Renamed.test_renamed")

    def test_publishes_only_end_to_end_test_methods(self) -> None:
        for slug, test in documentation.DOCUMENTED_DEMOS.items():
            with self.subTest(slug=slug):
                self.assertRegex(test, r"\AEndToEndTests\.test_\w+\.\w+\.test_\w+\Z")

    def test_rejects_a_slug_that_is_not_kebab_case(self) -> None:
        for slug in ("Tap Here", "tap_here", "-tap", "tap-", ""):
            with self.subTest(slug=slug):
                with self.assertRaisesRegex(ValueError, "kebab-case"):
                    Demo(slug=slug, title="Title", summary="Summary")

    def test_rejects_a_demo_without_a_title_or_summary(self) -> None:
        with self.assertRaisesRegex(ValueError, "title and a summary"):
            Demo(slug="tap-here", title="", summary="Summary")
        with self.assertRaisesRegex(ValueError, "title and a summary"):
            Demo(slug="tap-here", title="Title", summary="")

    def test_has_no_demo_for_an_undocumented_test(self) -> None:
        class Undocumented(unittest.TestCase):
            def test_undocumented(self) -> None: ...

        self.assertIsNone(demo_for(Undocumented("test_undocumented")))


class IdentityTests(unittest.TestCase):
    """One test has one published name, whichever build imported it."""

    def test_trims_a_repository_path_prefix(self) -> None:
        published = "EndToEndTests.test_system.OpenUrlTests.test_opening_a_url"

        self.assertEqual(test_identity(f"{PATH_PREFIX}{published}"), published)

    def test_leaves_an_identity_that_starts_at_the_suite_alone(self) -> None:
        published = "EndToEndTests.test_system.OpenUrlTests.test_opening_a_url"

        self.assertEqual(test_identity(published), published)

    def test_accepts_a_declaration_from_a_module_imported_by_path(self) -> None:
        published = "EndToEndTests.test_published.Cases.test_one"

        def method() -> None: ...

        method.__module__ = f"{PATH_PREFIX}EndToEndTests.test_published"
        method.__qualname__ = "Cases.test_one"

        with mock.patch.dict(
            documentation.DOCUMENTED_DEMOS, {"tap-here": published}, clear=True
        ):
            documented_demo(slug="tap-here", title="Title", summary="A summary")(method)

        demo = getattr(method, documentation.DEMO_ATTRIBUTE)
        self.assertEqual(demo.slug, "tap-here")


class PublishedInventoryTests(unittest.TestCase):
    """Every declaration in the suite, against everything the table publishes.

    The decorator only sees one declaration at a time, so the table can still
    name a test that no longer declares anything. Importing the decorated
    modules is what makes the whole inventory comparable.
    """

    def test_the_table_and_the_declarations_agree(self) -> None:
        declared: dict[str, str] = {}
        for module in self.decorated_modules():
            for case in vars(module).values():
                if not (isinstance(case, type) and issubclass(case, unittest.TestCase)):
                    continue
                if case.__module__ != module.__name__:
                    continue
                for attribute, method in vars(case).items():
                    demo = getattr(method, documentation.DEMO_ATTRIBUTE, None)
                    if demo is None:
                        continue
                    declared[demo.slug] = test_identity(
                        f"{case.__module__}.{case.__qualname__}.{attribute}"
                    )

        self.assertEqual(declared, dict(documentation.DOCUMENTED_DEMOS))

    def decorated_modules(self) -> list[types.ModuleType]:
        """Every module the table names, which any target running this must have.

        An import that fails here is the contract going unchecked, so it fails
        the test rather than skipping it: a target that cannot see the
        declarations cannot hold them to the table.
        """
        names = sorted(
            {test.split(".")[1] for test in documentation.DOCUMENTED_DEMOS.values()}
        )
        return [importlib.import_module(f".{name}", __package__) for name in names]


class NormalisationTests(unittest.TestCase):
    def test_replaces_the_device_set_and_the_working_directory(self) -> None:
        text = f"set={DEVICE_SET}/{UDID}/data socket={WORKING_DIRECTORY}/companion.sock"

        self.assertEqual(
            normalise(text, rules()),
            f"set=$DEVICE_SET/{UDID_PLACEHOLDER}/data "
            "socket=$IDB_E2E_DIR/companion.sock",
        )

    def test_names_the_target_udid_and_anonymises_every_other_uuid(self) -> None:
        text = f"target {UDID} installed {OTHER_UUID}"

        self.assertEqual(
            normalise(text, rules()),
            f"target {UDID_PLACEHOLDER} installed {UUID_PLACEHOLDER}",
        )

    def test_replaces_timestamps_pids_and_addresses(self) -> None:
        text = "2026-09-16T13:03:34+01:00 pid 8123 at 0x00007ff8412c"

        self.assertEqual(
            normalise(text, rules()),
            "TIMESTAMP pid PID at 0xADDRESS",
        )

    def test_keeps_json_punctuation_around_a_temporary_path(self) -> None:
        text = '{"container": "/var/folders/ab/cd/T/install", "ok": true}'

        self.assertEqual(
            normalise(text, rules()),
            f'{{"container": "{TEMPORARY_PLACEHOLDER}", "ok": true}}',
        )

    def test_names_each_directory_of_the_run_separately(self) -> None:
        text = (
            f"log={ARTIFACTS}/companion.log socket={WORKING_DIRECTORY}/companion.sock "
            f"set={DEVICE_SET} config={HOME}/.idb/targets tmp={TEMPORARY_DIRECTORY}/x"
        )

        self.assertEqual(
            normalise(text, rules()),
            f"log={ARTIFACTS_PLACEHOLDER}/companion.log "
            "socket=$IDB_E2E_DIR/companion.sock set=$DEVICE_SET "
            f"config={HOME_PLACEHOLDER}/.idb/targets "
            f"tmp={TEMPORARY_PLACEHOLDER}/x",
        )

    def test_keeps_the_name_of_a_directory_that_only_starts_the_same_way(self) -> None:
        text = f"{WORKING_DIRECTORY}-other/companion.log"

        self.assertEqual(
            normalise(text, rules()),
            f"{TEMPORARY_PLACEHOLDER}/{WORKING_DIRECTORY.name}-other/companion.log",
        )

    def test_trims_no_punctuation_from_a_sentence_ending_in_a_path(self) -> None:
        text = "Wrote /var/folders/ab/cd/T/frame.png, then stopped."

        self.assertEqual(
            normalise(text, rules()),
            f"Wrote {TEMPORARY_PLACEHOLDER}, then stopped.",
        )

    def test_two_runs_normalise_to_the_same_text(self) -> None:
        def run(udid: str, session: str) -> str:
            return normalise(
                f'{{"udid": "{udid}", "log": "/tmp/{session}/companion.log"}}',
                normalisation_rules(udid, DEVICE_SET, Path(f"/tmp/{session}")),
            )

        self.assertEqual(
            run(UDID, "idb-e2e-4xdxnimi"), run(OTHER_UUID, "idb-e2e-zzzzzzzz")
        )


class CaptureTests(unittest.TestCase):
    def test_captures_normalised_text(self) -> None:
        captured = capture(f"booted {UDID}\n".encode(), rules())

        self.assertEqual(
            captured.as_json(),
            {"bytes": 44, "text": f"booted {UDID_PLACEHOLDER}\n", "truncated": False},
        )

    def test_truncates_long_output_and_says_so(self) -> None:
        captured = capture(b"x" * (MAXIMUM_CAPTURED_CHARACTERS + 10), rules())

        self.assertEqual(
            captured.as_json(),
            {
                "bytes": MAXIMUM_CAPTURED_CHARACTERS + 10,
                "text": "x" * MAXIMUM_CAPTURED_CHARACTERS,
                "truncated": True,
            },
        )

    def test_records_output_that_is_not_text_by_digest(self) -> None:
        captured = capture(BINARY_OUTPUT, rules())

        self.assertEqual(
            captured.as_json(),
            {
                "bytes": len(BINARY_OUTPUT),
                "binary": True,
                "sha256": (
                    "96630742f619e3a4e73672049c94fa9641449ed23ebf9848f7bc9f2f5c64f933"
                ),
            },
        )

    def test_records_no_digest_for_text_and_no_text_for_binary(self) -> None:
        self.assertNotIn("sha256", capture(b"plain", rules()).as_json())
        self.assertNotIn("text", capture(BINARY_OUTPUT, rules()).as_json())


class DemoCaseStub:
    """Drive IdbEndToEndTestCase.idb against a real trace, without a simulator."""

    idb = IdbEndToEndTestCase.idb
    note = IdbEndToEndTestCase.note
    run_client = IdbEndToEndTestCase.run_client
    _command_fields = IdbEndToEndTestCase._command_fields

    def __init__(self, recording: Recording, transcript: Transcript | None) -> None:
        self.recording = recording
        self.transcript = transcript
        self.companion = SimpleNamespace(address="/tmp/companion.sock")
        self.environment = SimpleNamespace(idb_bin=Path("/tmp/idb"), idb_args=())


@contextmanager
def trace(encoding: str = "auto") -> Iterator[Recording]:
    """A Recording writing a real trace, with the recorder process faked."""
    with tempfile.TemporaryDirectory() as directory:
        process = mock.Mock()
        process.poll.return_value = None
        process.returncode = 0
        process.stdin = io.BytesIO()
        with (
            mock.patch.object(
                recording_module.subprocess, "Popen", return_value=process
            ),
            mock.patch.dict(os.environ, {}, clear=True),
        ):
            recording = Recording(
                Path("/recorder"),
                UDID,
                DEVICE_SET,
                Path(directory),
                "suite",
                encoding,
            )
            try:
                yield recording
            finally:
                recording.trace.close()


def events(recording: Recording) -> list[dict[str, Any]]:
    return [
        json.loads(line) for line in Path(recording.trace.name).read_text().splitlines()
    ]


class RecordingContainerTests(unittest.TestCase):
    """The container each encoding is recorded in, and the report beside it."""

    def test_the_encodings_a_browser_plays_are_recorded_as_mpeg_4(self) -> None:
        for encoding in ("h264", "hevc"):
            with self.subTest(encoding=encoding), trace(encoding) as recording:
                self.assertEqual(recording.video.name, "suite.mp4")

    def test_the_encodings_the_recorder_confines_to_quicktime_stay_there(self) -> None:
        for encoding in ("mjpeg", "auto"):
            with self.subTest(encoding=encoding), trace(encoding) as recording:
                self.assertEqual(recording.video.name, "suite.mov")

    def test_the_recorder_is_asked_for_the_container_it_records(self) -> None:
        for encoding, suffix in CONTAINERS.items():
            with self.subTest(encoding=encoding), trace(encoding) as recording:
                argv = recording_module.subprocess.Popen.call_args.args[0]

                self.assertEqual(argv[2], str(recording.video))
                self.assertEqual(argv[argv.index("--encoding") + 1], encoding)
                self.assertTrue(argv[2].endswith(suffix))

    def test_an_encoding_the_recorder_does_not_write_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(recording_module.subprocess, "Popen") as spawn:
                with self.assertRaises(ValueError) as refusal:
                    Recording(
                        Path("/recorder"),
                        UDID,
                        DEVICE_SET,
                        Path(directory),
                        "suite",
                        "h265",
                    )

                spawn.assert_not_called()
            self.assertEqual(sorted(Path(directory).iterdir()), [])

        self.assertIn(f"{ENCODING_ENV}=h265", str(refusal.exception))
        self.assertIn("auto, h264, hevc, mjpeg", str(refusal.exception))

    def test_the_report_is_read_from_beside_the_recording(self) -> None:
        with trace("h264") as recording:
            Path(f"{recording.video}.json").write_text("{}\n")
            recording.stop()
            finished = self.finished(recording)

        self.assertEqual(finished["status"], "recorded")

    def test_a_recording_the_recorder_did_not_report_is_unavailable(self) -> None:
        with trace("h264") as recording:
            recording.stop()
            finished = self.finished(recording)

        self.assertEqual(finished["status"], "unavailable")

    def finished(self, recording: Recording) -> dict[str, Any]:
        return next(
            event
            for event in events(recording)
            if event["event"] == "recording_finished"
        )


class DemoTraceTests(unittest.IsolatedAsyncioTestCase):
    async def commands(
        self,
        transcript: Transcript | None,
        completed: Completed,
        argument: str = "https://example.com",
        **named: str,
    ) -> dict[str, Any]:
        with trace() as recording:
            recording.start_test("EndToEndTests.test_demo.DemoTests.test_demo")
            recording.demo("open-a-url", "Open a URL", "Open a URL on a simulator")
            case = DemoCaseStub(recording, transcript)
            with mock.patch.object(
                harness, "run", new=mock.AsyncMock(return_value=completed)
            ):
                await case.idb("open", argument, **named)
            recording.finish_test("passed")
            recorded = events(recording)
        return next(event for event in recorded if event["event"] == "command_finished")

    async def test_a_named_command_publishes_its_output(self) -> None:
        finished = await self.commands(
            Transcript(rules()),
            Completed(0, f"opened on {UDID}\n".encode(), b""),
            step="Open a URL on the simulator",
        )

        self.assertEqual(finished["step"], "Open a URL on the simulator")
        self.assertEqual(finished["stdout"]["text"], f"opened on {UDID_PLACEHOLDER}\n")
        self.assertEqual(finished["stderr"]["text"], "")

    async def test_a_named_command_publishes_a_normalised_argv(self) -> None:
        finished = await self.commands(
            Transcript(rules()),
            Completed(0, b"", b""),
            argument=f"{WORKING_DIRECTORY}/screenshot.png",
            step="Save a screenshot",
        )

        self.assertEqual(
            finished["argv"], ["idb", "open", "$IDB_E2E_DIR/screenshot.png"]
        )

    async def test_an_unnamed_command_is_not_published(self) -> None:
        finished = await self.commands(
            Transcript(rules()),
            Completed(0, b"a poll result\n", b""),
            argument=f"{WORKING_DIRECTORY}/screenshot.png",
        )

        self.assertNotIn("step", finished)
        self.assertNotIn("stdout", finished)
        self.assertEqual(
            finished["argv"], ["idb", "open", f"{WORKING_DIRECTORY}/screenshot.png"]
        )

    async def test_a_named_command_outside_a_demo_is_not_published(self) -> None:
        finished = await self.commands(
            None, Completed(0, b"output\n", b""), step="Open a URL on the simulator"
        )

        self.assertNotIn("step", finished)
        self.assertNotIn("stdout", finished)

    async def noted(self, transcript: Transcript | None) -> list[dict[str, Any]]:
        with trace() as recording:
            recording.start_test("EndToEndTests.test_demo.DemoTests.test_demo")
            recording.demo("open-a-url", "Open a URL", "Open a URL on a simulator")
            case = DemoCaseStub(recording, transcript)
            with mock.patch.object(
                harness, "run", new=mock.AsyncMock(return_value=Completed(0, b"", b""))
            ):
                await case.idb("open", "https://example.com", step="Open a URL")
            case.note(f"Safari opened on {UDID}", UDID, "Safari")
            recording.finish_test("passed")
            recorded = events(recording)
        return [event for event in recorded if event["event"] == "step_note"]

    async def test_a_note_is_recorded_after_the_step_it_describes(self) -> None:
        noted = await self.noted(Transcript(rules()))

        self.assertEqual(len(noted), 1)
        self.assertEqual(noted[0]["text"], f"Safari opened on {UDID_PLACEHOLDER}")
        self.assertEqual(noted[0]["marks"], [UDID_PLACEHOLDER, "Safari"])

    async def test_a_note_outside_a_demo_is_not_recorded(self) -> None:
        self.assertEqual(await self.noted(None), [])

    async def test_the_demo_event_carries_what_the_website_publishes(self) -> None:
        with trace() as recording:
            recording.start_test("EndToEndTests.test_demo.DemoTests.test_demo")
            recording.demo("open-a-url", "Open a URL", "Open a URL on a simulator")
            recorded = events(recording)

        demo = next(event for event in recorded if event["event"] == "demo")
        self.assertEqual(
            {key: demo[key] for key in ("test", "slug", "title", "summary")},
            {
                "test": "EndToEndTests.test_demo.DemoTests.test_demo",
                "slug": "open-a-url",
                "title": "Open a URL",
                "summary": "Open a URL on a simulator",
            },
        )
