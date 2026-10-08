# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Answer questions about `TestPlan.json` for `build.sh test` and the CI matrix.

The plan is generated from the Buck graph beside `project.yml`, so a new test
target reaches both without either naming it. Runs on the system `python3`
`build.sh` finds, so it keeps to syntax that macOS's 3.9 accepts.
"""

from __future__ import annotations

import argparse
import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PLAN = Path("TestPlan.json")

# The GitHub-hosted runner each runner class in the plan runs on.
RUNNER_LABELS: Mapping[str, str] = {"standard": "macos-26", "large": "macos-26-xlarge"}


@dataclass(frozen=True)
class TestTarget:
    name: str
    booted_simulator: bool
    prerequisites: tuple[str, ...]
    runner: str


@dataclass(frozen=True)
class TestPlan:
    schemes: Mapping[str, tuple[str, ...]]
    test_targets: Mapping[str, TestTarget]

    @classmethod
    def load(cls, path: Path) -> TestPlan:
        document = json.loads(path.read_text())
        return cls(
            schemes={
                name: tuple(targets) for name, targets in document["schemes"].items()
            },
            test_targets={
                name: TestTarget(
                    name=name,
                    booted_simulator=fields["bootedSimulator"],
                    prerequisites=tuple(fields["prerequisites"]),
                    runner=fields["runner"],
                )
                for name, fields in document["testTargets"].items()
            },
        )

    def prerequisites(self, scheme: str) -> list[str]:
        """The `build.sh` steps the scheme's bundles need run first, each once."""
        return sorted(
            {
                step
                for target in self.schemes[scheme]
                for step in self.test_targets[target].prerequisites
            }
        )

    def display_name(self, target: str) -> str:
        """The framework a test target tests, then its suite when it has one.

        The framework is the longest scheme name the target's name starts with, so
        `FBSimulatorControlSmokeTests` reads as `FBSimulatorControl Smoke`; a target
        no framework scheme prefixes is named for itself.
        """
        base = target[: -len("Tests")] if target.endswith("Tests") else target
        frameworks = [
            scheme
            for scheme in self.schemes
            if scheme not in self.test_targets and base.startswith(scheme)
        ]
        if not frameworks:
            return base
        framework = max(frameworks, key=len)
        suite = base[len(framework) :]
        return f"{framework} {suite}" if suite else framework

    def matrix(self) -> list[dict[str, object]]:
        """One CI job per test target, each run through its own scheme."""
        return [
            {
                "name": self.display_name(target.name),
                "target": target.name,
                "bootedSimulator": target.booted_simulator,
                "runsOn": RUNNER_LABELS[target.runner],
            }
            for target in sorted(self.test_targets.values(), key=lambda t: t.name)
        ]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", type=Path, default=DEFAULT_PLAN)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("schemes", help="every scheme build.sh test accepts")
    commands.add_parser("test-targets", help="every test target, as test_all runs them")
    commands.add_parser("matrix", help="the CI job matrix, as GitHub Actions output")
    prerequisites = commands.add_parser(
        "prerequisites",
        help="the build.sh steps that build what the scheme's bundles copy",
    )
    prerequisites.add_argument("scheme")
    arguments = parser.parse_args(argv)
    plan = TestPlan.load(arguments.plan)
    if arguments.command == "schemes":
        print("\n".join(sorted(plan.schemes)))
    elif arguments.command == "test-targets":
        print("\n".join(sorted(plan.test_targets)))
    elif arguments.command == "matrix":
        print(f"targets={json.dumps(plan.matrix())}")
    elif arguments.scheme not in plan.schemes:
        parser.error(f"unknown scheme: {arguments.scheme}")
    else:
        print("\n".join(plan.prerequisites(arguments.scheme)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
