# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Names the newest iOS simulator the machine can create.

The end-to-end suite consumes a simulator it does not create, so what it runs
against is whatever the harness around it picked. Naming the runtime rather
than leaving it implicit is what keeps that "the newest iOS available here"
instead of "whatever a device type defaulted to on the image of the day".

Prints two identifiers, device type first, for a caller to hand to
``simctl create``:

    xcrun simctl create name $(python3 EndToEndTests/newest_simulator.py)
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any

IOS_RUNTIME_PREFIX = "com.apple.CoreSimulator.SimRuntime.iOS-"


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


def main() -> int:
    listing = json.loads(
        subprocess.run(
            ["xcrun", "simctl", "list", "--json", "runtimes"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    try:
        runtime = newest_runtime(listing.get("runtimes", []))
        device_type = newest_iphone(runtime)
    except NoSimulatorError as error:
        print(error, file=sys.stderr)
        return 1
    print(f"{device_type['identifier']} {runtime['identifier']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
