#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from argparse import ArgumentParser, Namespace

import idb.common.plugin as plugin
from idb.cli import BaseCommand
from idb.common.types import IdbException


_AGENT_GUIDE = """\
idb agent guide

This guide is for coding agents and automation driving iOS simulators and
devices through idb. The CLI is the source of truth for its own commands:
`idb <command> --help` describes every flag; this guide describes the
workflow expectations that make automated sessions reliable.

Read before acting
- Prefer reading the accessibility tree over screenshots:
  `idb ui describe-all --json` returns every element on screen.
- `--format nested` preserves the element hierarchy; `--format complete`
  returns a consolidated document that also names the backend that served
  the read.
- Narrow reads: `idb ui describe <marker>` describes one element by its
  accessibility identity; `idb ui describe-point <x> <y>` by position.

Interact by element identity, not coordinates
- `idb ui tap <marker> --match-key AXUniqueId` resolves the accessibility
  element and invokes its press action, so it does not drift with layout,
  scale, or scroll position the way coordinate taps do.
- `idb ui set-value` and `idb ui scroll` address elements the same way.
- When an element exposes no AXUniqueId but you can name what is on
  screen, tap it by its visible label: `idb ui tap "<label>"` - the label
  is the default match key, and it works on surfaces that never set
  identifiers.
- Coordinate taps (`idb ui tap <x> <y>`) are a last resort for targets
  with neither identifier nor label. When one is genuinely required,
  record why with `--reason`.

Record intent
- `--reason "<why>"` is accepted by every command and records the intent
  of the invocation for the operators of the host being driven. Supply it
  whenever the purpose of a command is not obvious from the command
  itself, and always for coordinate taps and screenshots.

Identify yourself
- idb recognizes standard agent environment signals, in priority order:
  AI_AGENT (user-agent style, `AI_AGENT=<product>/<version>/<mode>` - the
  preferred contract), AGENT (a bare product name), CODING_AGENT_METADATA
  (the structured channel: comma-separated key=value pairs, for example
  `CODING_AGENT_METADATA=id=<agent-product>,session_id=<uuid>`, carrying
  session and invocation identity), and CLAUDECODE=1.
- If your harness sets none of these, export one so tooling can
  distinguish agent traffic from human sessions.
"""

# Topic key -> (one-line summary, body). Subtopic words join with "-", so
# `idb help agent performance` resolves the key "agent-performance".
_TOPICS: dict[str, tuple[str, str]] = {
    "agent": ("guidance for coding agents and automation driving idb", _AGENT_GUIDE),
}


def _topic_list() -> str:
    lines = ["Topics served by this idb build:"]
    for key, (summary, _) in sorted(_TOPICS.items()):
        lines.append(f"  {key} - {summary}")
    lines.append("Run `idb help <topic>` to read one.")
    return "\n".join(lines)


class HelpCommand(BaseCommand):
    @property
    def description(self) -> str:
        return "Topic guides served by the CLI itself (see `idb help agent`)"

    @property
    def name(self) -> str:
        return "help"

    def add_parser_arguments(self, parser: ArgumentParser) -> None:
        parser.add_argument(
            "topic",
            nargs="*",
            help="Topic words, joined to a key (`agent performance` reads "
            "the agent-performance topic). Omit to list topics.",
        )
        super().add_parser_arguments(parser)

    async def _run_impl(self, args: Namespace) -> None:
        key = "-".join(args.topic)
        if not key:
            print(_topic_list())
            return
        topic = _TOPICS.get(key)
        # Plugins may extend a topic or serve topics of their own, so an
        # unknown key only fails once the plugins had their say.
        contributed = plugin.get_agent_instructions(names=list(args.topic))
        if topic is None and not contributed:
            raise IdbException(f"No help topic '{key}'.\n{_topic_list()}")
        sections = [
            section for section in (topic[1] if topic else "", contributed) if section
        ]
        print("\n".join(sections))
