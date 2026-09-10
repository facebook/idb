# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Collect what explains a failed end-to-end run.

A companion that dies mid-run takes every later command with it, and its own
log stops at whatever it was serving rather than saying why. The crash report
is the only account of that: its presence separates a signal from an orderly
exit, which the log cannot.

The rest is for the failures that are not crashes, which the companion log
cannot explain either. A read that never arrives is accounted for on the
simulator's side, and the guest bridge is a process of its own that reports
inside the device rather than onto the host.

Collecting this costs a run that has already failed and saves a whole round
trip, which for a suite that only runs after an export is most of a day.

    python3 -m CI.collect_diagnostics --output "$RUNNER_TEMP/diagnostics"
"""

from __future__ import annotations

import argparse
import glob
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from .provision_simulator import simctl_argv

# The guest's log is unbounded and only the run's own window is evidence of
# anything.
SIMULATOR_LOG_WINDOW = "10m"

Run = Callable[[Sequence[str]], str]


@dataclass(frozen=True)
class Copy:
    """Whatever a glob matches, which may be nothing."""

    pattern: str

    def collect(self, output: Path, run: Run) -> list[str]:
        names = []
        for path in sorted(glob.glob(self.pattern)):
            name = os.path.basename(path)
            shutil.copy(path, output / name)
            names.append(name)
        return names


@dataclass(frozen=True)
class Capture:
    """A command's output, whatever it exits with."""

    name: str
    argv: tuple[str, ...]

    def collect(self, output: Path, run: Run) -> list[str]:
        (output / self.name).write_text(run(self.argv))
        return [self.name]


Source = Copy | Capture


def host_sources(*, home: Path, companion_root: Path) -> list[Source]:
    """What is on the host, and so readable whether or not a simulator ran."""
    reports = home / "Library" / "Logs" / "DiagnosticReports"
    return [
        Copy(str(companion_root / "idb-e2e-*" / "companion.log")),
        Copy(str(reports / "idb_companion*.ips")),
        Copy(str(reports / "SimulatorFrameworkBridge*.ips")),
    ]


def simulator_sources(*, device_set: Path, udid: str) -> list[Source]:
    """What only the provisioned simulator can account for."""
    return [
        Copy(str(device_set / udid / "data/Library/Logs/CrashReporter/*.ips")),
        Capture("devices.txt", tuple(simctl_argv(device_set, "list", "devices"))),
        Capture(
            "simulator-log.txt",
            tuple(
                simctl_argv(
                    device_set,
                    "spawn",
                    udid,
                    "log",
                    "show",
                    "--last",
                    SIMULATOR_LOG_WINDOW,
                    "--style",
                    "compact",
                )
            ),
        ),
    ]


def diagnostic_plan(
    *,
    home: Path,
    companion_root: Path,
    device_set: Path | None = None,
    udid: str | None = None,
) -> list[Source]:
    """Everything worth keeping from a failed run, in the order it is read.

    A run that failed before it was provisioned has no simulator to read, but
    still has a companion log and a crash report on the host.
    """
    plan = host_sources(home=home, companion_root=companion_root)
    if device_set is not None and udid:
        plan += simulator_sources(device_set=device_set, udid=udid)
    return plan


def collect(plan: Sequence[Source], output: Path, run: Run) -> list[str]:
    """Run the plan, reporting what was collected.

    A source that cannot be read is reported and skipped rather than raised:
    this runs only because something has already failed, and a collection that
    failed the job would replace the failure being diagnosed with itself.
    """
    output.mkdir(parents=True, exist_ok=True)
    collected: list[str] = []
    for source in plan:
        try:
            collected.extend(source.collect(output, run))
        except OSError as error:
            print(f"{source} could not be collected: {error}", file=sys.stderr)
    return collected


def _run(argv: Sequence[str]) -> str:
    completed = subprocess.run(list(argv), capture_output=True, text=True, check=False)
    return completed.stdout + completed.stderr


def _optional_path(value: str | None) -> Path | None:
    return None if not value else Path(value)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device-set", type=Path)
    parser.add_argument("--udid")
    parser.add_argument("--companion-root", type=Path, default=Path("/tmp"))
    arguments = parser.parse_args(argv)

    device_set = arguments.device_set or _optional_path(
        os.environ.get("DEVICE_SET_PATH")
    )
    udid = arguments.udid or os.environ.get("DEVICE_UDID")
    if device_set is None or not udid:
        print(
            "No simulator named by --device-set/--udid or DEVICE_SET_PATH/"
            "DEVICE_UDID; collecting host-side diagnostics only",
            file=sys.stderr,
        )

    plan = diagnostic_plan(
        home=Path.home(),
        companion_root=arguments.companion_root,
        device_set=device_set,
        udid=udid,
    )
    for name in collect(plan, arguments.output, _run):
        print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
