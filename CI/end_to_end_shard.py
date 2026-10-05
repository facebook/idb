# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Name the end-to-end test modules that one CI shard runs.

Each shard runs on its own runner. A module no shard names runs
in the remainder shard, so a new module is never left out of CI.
"""

from __future__ import annotations

import argparse
from collections.abc import Mapping, Sequence
from pathlib import Path

# `demos` holds every documented demo and nothing else, so it is the one
# shard whose run documents them, and the site depends on no other test.
# `system` keeps the prompt-raising permission tests away from the others'
# simulator. `install` drives a companion targeting the Mac and needs no
# simulator at all.
SHARDS: Mapping[str, tuple[str, ...]] = {
    "demos": ("test_demos",),
    "ui": ("test_accessibility", "test_services"),
    "system": ("test_system",),
    "install": ("test_install",),
}
REMAINDER = "apps"


def modules(shard: str, directory: Path) -> list[str]:
    if shard == REMAINDER:
        claimed = {module for named in SHARDS.values() for module in named}
        names = sorted(
            path.stem
            for path in directory.glob("test_*.py")
            if path.stem not in claimed
        )
    else:
        names = SHARDS[shard]
    return [f"{directory.name}.{name}" for name in names]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shard", choices=[*SHARDS, REMAINDER])
    parser.add_argument("--directory", type=Path, default=Path("EndToEndTests"))
    arguments = parser.parse_args(argv)
    print(" ".join(modules(arguments.shard, arguments.directory)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
