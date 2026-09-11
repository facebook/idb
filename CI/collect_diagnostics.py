# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Collect companion logs, crash reports and simulator output after a failed run.

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

# Limit simulator log output to the most recent ten minutes.
SIMULATOR_LOG_WINDOW = "10m"

Run = Callable[[Sequence[str]], str]


@dataclass(frozen=True)
class Copy:
    """Copy files matching a glob into the output directory."""

    root: Path
    pattern: str
    destination: str = ""

    def collect(self, output: Path, run: Run) -> list[str]:
        names = []
        for path in sorted(glob.glob(str(self.root / self.pattern))):
            relative_path = Path(self.destination) / Path(path).relative_to(self.root)
            target = output / relative_path
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(path, target)
            names.append(str(relative_path))
        return names


@dataclass(frozen=True)
class Capture:
    """Save command output to a named file."""

    name: str
    argv: tuple[str, ...]

    def collect(self, output: Path, run: Run) -> list[str]:
        (output / self.name).write_text(run(self.argv))
        return [self.name]


Source = Copy | Capture


def host_sources(*, home: Path, companion_root: Path) -> list[Source]:
    reports = home / "Library" / "Logs" / "DiagnosticReports"
    return [
        Copy(companion_root, "idb-e2e-*/companion.log", "companions"),
        Copy(reports, "idb_companion*.ips", "host-crashes"),
        Copy(reports, "SimulatorFrameworkBridge*.ips", "host-crashes"),
    ]


def simulator_sources(*, device_set: Path, udid: str) -> list[Source]:
    return [
        Copy(
            device_set / udid / "data/Library/Logs/CrashReporter",
            "*.ips",
            "simulator-crashes",
        ),
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
    """List host diagnostics, adding simulator diagnostics when a device is known."""
    plan = host_sources(home=home, companion_root=companion_root)
    if device_set is not None and udid:
        plan += simulator_sources(device_set=device_set, udid=udid)
    return plan


def collect(plan: Sequence[Source], output: Path, run: Run) -> list[str]:
    """Collect available diagnostics, reporting and skipping unreadable sources."""
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
