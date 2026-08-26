#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import os


AI_AGENT_ENV = "AI_AGENT"
AGENT_ENV = "AGENT"
CODING_AGENT_METADATA_ENV = "CODING_AGENT_METADATA"
CLAUDECODE_ENV = "CLAUDECODE"


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


def agent_product() -> str | None:
    """The agent product driving this process, or None for a human session.

    Standard signals are checked in a fixed priority order, values taken
    verbatim with literal comparisons:
    1. ``AI_AGENT`` - user-agent style ``product/version/mode``; the product
       is the leading segment. The preferred contract for harnesses.
    2. ``AGENT`` - a bare product name, the generic fallback signal.
    3. ``CODING_AGENT_METADATA`` - the structured channel; its ``id`` key
       names the product and other keys carry session identity.
    4. ``CLAUDECODE`` - presence signal; the value must be exactly ``"1"``.
    """
    ai_agent = os.environ.get(AI_AGENT_ENV, "")
    if ai_agent:
        product = ai_agent.split("/", 1)[0]
        return product if product else ai_agent
    agent = os.environ.get(AGENT_ENV, "")
    if agent:
        return agent
    metadata_id = agent_metadata().get("id")
    if metadata_id:
        return metadata_id
    if os.environ.get(CLAUDECODE_ENV) == "1":
        return "claude-code"
    return None


def is_agent() -> bool:
    return agent_product() is not None
