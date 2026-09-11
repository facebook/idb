# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Boot a simulator using the newest available iOS runtime and supported iPhone.

Print KEY=value lines for the caller to export:

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
    """No suitable simulator is available, or creation returned no UDID."""


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
    # Prefer the base model when multiple variants share a generation.
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
    scope = [] if device_set is None else ["--set", str(device_set)]
    return ["xcrun", "simctl", *scope, *args]


def environment_lines(
    udid: str, device_set: Path | None, prefix: str = ""
) -> list[str]:
    """Format the UDID and optional device set as environment variables."""
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
    """Create a simulator and wait for bootstatus before returning its environment."""
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
        raise NoSimulatorError(f"simctl create {name} returned no UDID")
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
        help="create the simulator in this device set (default: the system device set)",
    )
    parser.add_argument(
        "--env-prefix",
        default="",
        help="prefix for output variable names, such as TEST_RUNNER_ for xcodebuild",
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
