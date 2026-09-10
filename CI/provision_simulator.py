# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Create and boot the simulator the end-to-end suite runs against.

The suite consumes a booted simulator and never creates one, so this is what
supplies it. It lives outside ``EndToEndTests`` because provisioning is the
precondition for the tests rather than one of them: here, the selection and
the ``simctl`` sequence are covered by tests that need no simulator, and the
suite's own discovery can never pick them up.

The runtime is named rather than defaulted so that what idb is tested against
is the newest iOS the machine offers, not whatever a hardcoded device type
happens to pair with once the image moves on.

Prints the environment the caller should export, one ``KEY=value`` per line:

    python3 -m CI.provision_simulator --name e2e >> "$GITHUB_ENV"
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Sequence

IOS_RUNTIME_PREFIX = "com.apple.CoreSimulator.SimRuntime.iOS-"

Run = Callable[[Sequence[str]], str]


class NoSimulatorError(Exception):
    """Nothing on this machine can run the suite."""


def _version(runtime: dict[str, Any]) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", runtime.get("version", "")))


def newest_runtime(runtimes: list[dict[str, Any]]) -> dict[str, Any]:
    available = [
        runtime
        for runtime in runtimes
        if runtime.get("isAvailable")
        and str(runtime.get("identifier", "")).startswith(IOS_RUNTIME_PREFIX)
    ]
    if not available:
        raise NoSimulatorError("No iOS runtime is available")
    return max(available, key=_version)


def _rank(name: str) -> tuple[int, bool] | None:
    match = re.fullmatch(r"iPhone (\d+)( .+)?", name)
    if match is None:
        return None
    # The base model over its Pro/Plus/Max variants: the suite exercises idb
    # rather than a screen size, and the base model is the one every generation
    # has.
    return (int(match.group(1)), match.group(2) is None)


def newest_iphone(runtime: dict[str, Any]) -> dict[str, Any]:
    ranked = [
        (rank, device_type)
        for device_type in runtime.get("supportedDeviceTypes", [])
        if (rank := _rank(str(device_type.get("name", "")))) is not None
    ]
    if not ranked:
        raise NoSimulatorError(
            f"{runtime.get('name')} supports no numbered iPhone device type"
        )
    return max(ranked, key=lambda entry: entry[0])[1]


def simctl_argv(device_set: Path | None, *args: str) -> list[str]:
    """A ``simctl`` command line, scoped to ``device_set`` when there is one."""
    scope = [] if device_set is None else ["--set", str(device_set)]
    return ["xcrun", "simctl", *scope, *args]


def environment_lines(
    udid: str, device_set: Path | None, prefix: str = ""
) -> list[str]:
    """The ``KEY=value`` lines naming what was provisioned.

    The device set is named alongside the UDID so that a consumer can never
    resolve the UDID in a set other than the one it was created in.
    """
    lines = []
    if device_set is not None:
        lines.append(f"{prefix}DEVICE_SET_PATH={device_set}")
    lines.append(f"{prefix}DEVICE_UDID={udid}")
    return lines


def provision(
    run: Run,
    *,
    name: str,
    device_set: Path | None = None,
    env_prefix: str = "",
) -> list[str]:
    """Create, boot and wait for a simulator; return its environment lines.

    ``bootstatus`` rather than ``boot`` alone: ``boot`` returns the moment the
    boot is underway, and work handed to a simulator before it finishes waits
    rather than failing.
    """
    listing = json.loads(run(["xcrun", "simctl", "list", "--json", "runtimes"]))
    runtime = newest_runtime(listing.get("runtimes", []))
    device_type = newest_iphone(runtime)
    print(
        f"Creating {device_type['identifier']} on {runtime['identifier']}",
        file=sys.stderr,
    )
    udid = run(
        simctl_argv(
            device_set, "create", name, device_type["identifier"], runtime["identifier"]
        )
    ).strip()
    if not udid:
        raise NoSimulatorError(f"simctl create {name} named no simulator")
    run(simctl_argv(device_set, "boot", udid))
    run(simctl_argv(device_set, "bootstatus", udid))
    return environment_lines(udid, device_set, env_prefix)


def _run(argv: Sequence[str]) -> str:
    return subprocess.run(list(argv), check=True, capture_output=True, text=True).stdout


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="the simulator's name")
    parser.add_argument(
        "--device-set",
        type=Path,
        default=None,
        help="a device set to create the simulator in, kept clear of anything "
        "else on the machine; the default set is used without it",
    )
    parser.add_argument(
        "--env-prefix",
        default="",
        help="prefix for the printed variable names, for consumers that only "
        "receive a prefixed subset of the environment",
    )
    arguments = parser.parse_args(argv)

    if arguments.device_set is not None:
        arguments.device_set.mkdir(parents=True, exist_ok=True)
    try:
        lines = provision(
            _run,
            name=arguments.name,
            device_set=arguments.device_set,
            env_prefix=arguments.env_prefix,
        )
    except NoSimulatorError as error:
        print(error, file=sys.stderr)
        return 1
    for line in lines:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
