# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Declare which end-to-end tests document idb, and record what they ran.

A test decorated with `documented_demo` is the only source of truth for one
demo on the website. The commands it names, with `idb(..., step=...)`, become
that demo's published transcript, so the documentation cannot drift from what
idb actually does without the test failing first.

DOCUMENTED_DEMOS is the other half of that contract, and it is enforced in
both directions. Decorating a test that the table does not publish, or that
the table publishes under a different name, fails as the suite is imported.
A demo the table publishes but no passing test performed fails the generator
that builds the website, so a deleted or broken demo blocks publication
rather than leaving stale documentation up.

Captured output is normalised before it is recorded: run-specific values are
replaced with placeholders so two runs of the same demo produce identical
text, and output that is not text is recorded by digest rather than embedded
as bytes.

Only a command that runs to completion can be a step. The streaming commands
the suite drives are read while they are still running and never have a final
stdout to publish, so a demo names the commands around them instead.
"""

from __future__ import annotations

import hashlib
import re
import unittest
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TypeVar

DEMO_ATTRIBUTE = "__idb_documented_demo__"

# The demos the website publishes, and the test that performs each one.
DOCUMENTED_DEMOS: Mapping[str, str] = {
    "open-a-url": (
        "EndToEndTests.test_system.OpenUrlTests"
        ".test_opening_a_url_launches_the_app_that_handles_it"
    ),
    "scroll-a-list": (
        "EndToEndTests.test_accessibility.AccessibilityTests"
        ".test_ui_scroll_moves_settings_rows_down_and_up"
    ),
    "tap-by-accessibility-id": (
        "EndToEndTests.test_accessibility.AccessibilityTests"
        ".test_ui_tap_opens_general_by_marker"
    ),
}

PACKAGE = "EndToEndTests"

MAXIMUM_CAPTURED_CHARACTERS = 4096

UDID_PLACEHOLDER = "UDID"
UUID_PLACEHOLDER = "00000000-0000-0000-0000-000000000000"
DEVICE_SET_PLACEHOLDER = "$DEVICE_SET"
WORKING_DIRECTORY_PLACEHOLDER = "$IDB_E2E_DIR"
ARTIFACTS_PLACEHOLDER = "$IDB_E2E_ARTIFACTS"
TEMPORARY_PLACEHOLDER = "$TMPDIR"
HOME_PLACEHOLDER = "$HOME"

_SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")
_UUID = re.compile(
    r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", re.IGNORECASE
)
# A path ends where a character that cannot be in one begins, so a trailing
# comma, quote or full stop in the surrounding text is left alone.
_TEMPORARY_DIRECTORY = re.compile(
    r"(?:/private)?/var/folders/[A-Za-z0-9+._/-]*[A-Za-z0-9+_/-]"
)
# What may follow a directory inside a longer path: not a character that would
# make it a different directory whose name merely starts the same way.
_PATH_BOUNDARY = r"(?![A-Za-z0-9._-])"
_TIMESTAMP = re.compile(
    r"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"
)
_ADDRESS = re.compile(r"0x[0-9a-f]{6,}", re.IGNORECASE)
_PID = re.compile(r"(?<=\bpid )\d+", re.IGNORECASE)

_Method = TypeVar("_Method", bound=Callable[..., Any])


@dataclass(frozen=True)
class Demo:
    """One documented journey through idb, owned by the test that performs it."""

    slug: str
    title: str
    summary: str

    def __post_init__(self) -> None:
        if not _SLUG.match(self.slug):
            raise ValueError(f"Demo slug {self.slug!r} is not kebab-case")
        if not self.title or not self.summary:
            raise ValueError(f"Demo {self.slug!r} needs both a title and a summary")

    def as_json(self) -> dict[str, str]:
        return {"slug": self.slug, "title": self.title, "summary": self.summary}


def test_identity(identity: str) -> str:
    """The name one test has whichever build imported it.

    The same module is `EndToEndTests.test_system` to a checkout and
    `fbobjc.Tools.idb.Source.EndToEndTests.test_system` to a build that imports
    it by repository path. The published table names one test, so every
    identity is trimmed back to the suite's own package before it is compared,
    recorded or published.
    """
    marker = f".{PACKAGE}."
    index = identity.find(marker)
    if index < 0:
        return identity
    return identity[index + 1 :]


def documented_demo(
    slug: str, title: str, summary: str
) -> Callable[[_Method], _Method]:
    """Mark a test method as the source of a documented demo."""
    demo = Demo(slug=slug, title=title, summary=summary)

    def decorate(method: _Method) -> _Method:
        test = test_identity(f"{method.__module__}.{method.__qualname__}")
        published = DOCUMENTED_DEMOS.get(slug)
        if published is None:
            raise ValueError(
                f"{test} declares demo {slug!r}, which the website does not "
                "publish; add it to DOCUMENTED_DEMOS"
            )
        if published != test:
            raise ValueError(
                f"Demo {slug!r} is published as {published} but declared by {test}"
            )
        setattr(method, DEMO_ATTRIBUTE, demo)
        return method

    return decorate


def demo_for(case: unittest.TestCase) -> Demo | None:
    """The demo the running test method declares, if it declares one."""
    method = getattr(case, case._testMethodName, None)
    return getattr(method, DEMO_ATTRIBUTE, None)


@dataclass(frozen=True)
class Rule:
    """One substitution that removes a run-specific value from captured output."""

    pattern: re.Pattern[str]
    replacement: str


def normalisation_rules(
    udid: str,
    device_set: Path,
    working_directory: Path,
    artifacts: Path | None = None,
    home: Path | None = None,
    temporary_directory: Path | None = None,
) -> tuple[Rule, ...]:
    """Substitutions that make one run's captured output identical to the next.

    Each directory keeps its own placeholder rather than sharing one, so a
    reader can tell which of the run's directories a published path was in.
    A directory the caller does not have contributes no rule.
    """
    candidates = (
        (device_set, DEVICE_SET_PLACEHOLDER),
        (working_directory, WORKING_DIRECTORY_PLACEHOLDER),
        (artifacts, ARTIFACTS_PLACEHOLDER),
        (temporary_directory, TEMPORARY_PLACEHOLDER),
        (home, HOME_PLACEHOLDER),
    )
    # Longest first, so a directory nested inside another still resolves to the
    # more specific placeholder.
    directories = sorted(
        (
            (str(directory), placeholder)
            for directory, placeholder in candidates
            if directory is not None
        ),
        key=lambda entry: len(entry[0]),
        reverse=True,
    )
    return tuple(
        [
            Rule(re.compile(re.escape(directory) + _PATH_BOUNDARY), placeholder)
            for directory, placeholder in directories
        ]
        + [
            Rule(re.compile(re.escape(udid), re.IGNORECASE), UDID_PLACEHOLDER),
            Rule(_UUID, UUID_PLACEHOLDER),
            Rule(_TEMPORARY_DIRECTORY, TEMPORARY_PLACEHOLDER),
            Rule(_TIMESTAMP, "TIMESTAMP"),
            Rule(_ADDRESS, "0xADDRESS"),
            Rule(_PID, "PID"),
        ]
    )


def normalise(text: str, rules: Sequence[Rule]) -> str:
    for rule in rules:
        text = rule.pattern.sub(rule.replacement, text)
    return text


@dataclass(frozen=True)
class Text:
    """Captured output that decoded as UTF-8."""

    text: str
    truncated: bool


@dataclass(frozen=True)
class Binary:
    """Captured output that did not decode as UTF-8, recorded by digest."""

    sha256: str


Content = Text | Binary


@dataclass(frozen=True)
class Stream:
    """One captured stream of a documented command."""

    byte_count: int
    content: Content

    def as_json(self) -> dict[str, Any]:
        if isinstance(self.content, Binary):
            return {
                "bytes": self.byte_count,
                "binary": True,
                "sha256": self.content.sha256,
            }
        return {
            "bytes": self.byte_count,
            "text": self.content.text,
            "truncated": self.content.truncated,
        }


def capture(data: bytes, rules: Sequence[Rule]) -> Stream:
    """Record one stream of a documented command, normalised and bounded."""
    try:
        decoded = data.decode("utf-8")
    except UnicodeDecodeError:
        return Stream(len(data), Binary(hashlib.sha256(data).hexdigest()))
    text = normalise(decoded, rules)
    return Stream(
        len(data),
        Text(
            text[:MAXIMUM_CAPTURED_CHARACTERS],
            len(text) > MAXIMUM_CAPTURED_CHARACTERS,
        ),
    )


@dataclass(frozen=True)
class Transcript:
    """Captures the output of the commands a documented demo names."""

    rules: tuple[Rule, ...]

    def argv(self, argv: Sequence[str]) -> list[str]:
        """The command as the website shows it, run-specific values removed.

        A published command carries the socket, device set and udid this run
        used, so the argv needs the same substitutions as the output it
        produced or the two would disagree about the same path.
        """
        return [normalise(argument, self.rules) for argument in argv]

    def captures(self, stdout: bytes, stderr: bytes) -> dict[str, Any]:
        return {
            "stdout": capture(stdout, self.rules).as_json(),
            "stderr": capture(stderr, self.rules).as_json(),
        }
