# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Fail a staging benchmark run only on an order-of-magnitude regression.

Hosted runners are too noisy to hold a commit to a few percent, so the nightly job
checks each case's median throughput against a floor: half of what the slowest
source-and-format pair managed when the floor was set. The few-percent gate is
`staging-bench ab` on one host (README.md).
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from collections import defaultdict
from collections.abc import Sequence

# Extracted megabytes per second. Generous on purpose: this catches a route that falls
# off a cliff (a stream that stops being extracted as it arrives, a decoder that goes
# quadratic), not drift.
FLOOR_MB_PER_SECOND = 20.0


def failures(lines: Sequence[str], floor: float = FLOOR_MB_PER_SECOND) -> list[str]:
    """Each case whose median throughput is under `floor`, or that failed outright."""
    throughput: dict[str, list[float]] = defaultdict(list)
    failed: dict[str, int] = defaultdict(int)
    for line in lines:
        if not line.strip():
            continue
        measurement = json.loads(line)
        case = measurement["benchCase"]
        name = f"{case['source']} {case['format']} {case['shape']['megabytes']}x{case['shape']['files']} {case['contents']}"
        if measurement.get("failure") or measurement["wallSeconds"] <= 0:
            failed[name] += 1
            continue
        throughput[name].append(case["shape"]["megabytes"] / measurement["wallSeconds"])
    problems = [
        f"{name}: {count} failed runs" for name, count in sorted(failed.items())
    ]
    for name, values in sorted(throughput.items()):
        median = statistics.median(values)
        if median < floor:
            problems.append(
                f"{name}: {median:.0f} MB/s, under the {floor:.0f} MB/s floor"
            )
    return problems


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results")
    arguments = parser.parse_args(argv)
    with open(arguments.results) as results:
        problems = failures(results.readlines())
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
