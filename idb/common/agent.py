#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import os


CODING_AGENT_METADATA_ENV = "CODING_AGENT_METADATA"


def parse_agent_metadata(raw: str) -> dict[str, str]:
    """Parse a CODING_AGENT_METADATA value.

    Coding-agent launchers identify themselves to tooling by exporting
    comma-separated key=value pairs, for example
    ``id=<agent-product>,session_id=<uuid>``. Keys and values are opaque to
    idb; entries with an empty key or value are dropped.
    """
    parsed: dict[str, str] = {}
    for part in raw.split(","):
        (key, _, value) = part.partition("=")
        if key and value:
            parsed[key] = value
    return parsed


def agent_metadata() -> dict[str, str]:
    return parse_agent_metadata(os.environ.get(CODING_AGENT_METADATA_ENV, ""))


def is_agent() -> bool:
    return bool(agent_metadata())
