# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Rewrite the facebook/homebrew-fb tap formulae for a facebook/idb release.

The single source for formula rewriting: the Release workflow's bottle job
uses it to bump a tap working copy to the release being cut before building
bottles from it, and release tooling uses the same functions to write the
published tap commit. Standard library only, so it runs anywhere a python3
exists.

Every replacement is anchored and count-verified: if a formula's shape has
drifted from what the anchors expect, the rewrite raises FormulaError instead
of guessing, and nothing is modified.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

IDB_REPO = "facebook/idb"

COMPANION_ASSET = "idb-companion.macos-arm64.tar.gz"
FORMULAE = ("idb-companion.rb", "idb-cli.rb", "idb.rb")

TAG_RE = re.compile(r"^v\d+\.\d+\.\d+(?:\.(?:a|b|rc)\d+)?$")


class FormulaError(Exception):
    pass


def version_from_tag(tag):
    if not TAG_RE.match(tag):
        raise FormulaError(f"tag {tag!r} does not look like vX.Y.Z or vX.Y.Z.<a|b|rc>N")
    return tag[1:]


def pep440(version):
    # PyPI normalizes 1.5.0.b4 to 1.5.0b4; the wheel filename uses that form
    # while the formulae keep the release's own dotted form.
    return re.sub(r"\.((?:a|b|rc)\d+)$", r"\1", version)


def wheel_asset(version):
    return f"fb_idb-{pep440(version)}-py3-none-any.whl"


def _sub(text, pattern, replacement, expected, anchor, name):
    new, count = re.subn(pattern, lambda match: replacement, text)
    if count != expected:
        raise FormulaError(
            f"{name}: expected {expected} match(es) for {anchor}, found {count} — "
            "the formula shape has changed; refusing to rewrite anything"
        )
    return new


def _download_url(tag, asset):
    return f"https://github.com/{IDB_REPO}/releases/download/{tag}/{asset}"


def rewrite_companion(text, tag, sha):
    version = version_from_tag(tag)
    text = _sub(
        text,
        r'(?m)^  url "https://github\.com/facebook/idb/releases/download/v[^/"]+/idb-companion\.macos-arm64\.tar\.gz"$',
        f'  url "{_download_url(tag, COMPANION_ASSET)}"',
        1,
        "the companion tarball url",
        "idb-companion.rb",
    )
    text = _sub(
        text,
        r'(?m)^  version "[^"]+"$',
        f'  version "{version}"',
        1,
        "the version stanza",
        "idb-companion.rb",
    )
    return _sub(
        text,
        r'(?m)^  sha256 "[0-9a-f]{64}"$',
        f'  sha256 "{sha}"',
        1,
        "the top-level sha256",
        "idb-companion.rb",
    )


def rewrite_cli(text, tag, wheel_sha):
    version = version_from_tag(tag)
    url_line = f'url "{_download_url(tag, wheel_asset(version))}"'
    text = _sub(
        text,
        r'(?m)^  url "https://github\.com/facebook/idb/releases/download/v[^/"]+/fb_idb-[^"/]+-py3-none-any\.whl"$',
        f"  {url_line}",
        1,
        "the main wheel url",
        "idb-cli.rb",
    )
    text = _sub(
        text,
        r'(?m)^  version "[^"]+"$',
        f'  version "{version}"',
        1,
        "the version stanza",
        "idb-cli.rb",
    )
    text = _sub(
        text,
        r'(?m)^  sha256 "[0-9a-f]{64}"$',
        f'  sha256 "{wheel_sha}"',
        1,
        "the top-level sha256",
        "idb-cli.rb",
    )

    # The fb-idb resource must mirror the main url and sha byte-for-byte, or
    # Homebrew stops deduping the download. Rewrite it inside its own block so
    # the seven pinned dependency resources cannot be touched.
    block_match = re.search(r'(?s)^  resource "fb-idb" do\n.*?\n  end$', text, re.M)
    if block_match is None:
        raise FormulaError(
            'idb-cli.rb: the resource "fb-idb" block is missing — '
            "the formula shape has changed; refusing to rewrite anything"
        )
    block = block_match.group(0)
    block = _sub(
        block,
        r'(?m)^    url "https://github\.com/facebook/idb/releases/download/v[^/"]+/fb_idb-[^"/]+-py3-none-any\.whl"$',
        f"    {url_line}",
        1,
        "the fb-idb resource url",
        "idb-cli.rb",
    )
    block = _sub(
        block,
        r'(?m)^    sha256 "[0-9a-f]{64}"$',
        f'    sha256 "{wheel_sha}"',
        1,
        "the fb-idb resource sha256",
        "idb-cli.rb",
    )
    return text[: block_match.start()] + block + text[block_match.end() :]


def rewrite_idb(text, tag, wheel_sha):
    version = version_from_tag(tag)
    text = _sub(
        text,
        r'(?m)^  url "https://github\.com/facebook/idb/releases/download/v[^/"]+/fb_idb-[^"/]+-py3-none-any\.whl"$',
        f'  url "{_download_url(tag, wheel_asset(version))}"',
        1,
        "the wheel url",
        "idb.rb",
    )
    text = _sub(
        text,
        r'(?m)^  version "[^"]+"$',
        f'  version "{version}"',
        1,
        "the version stanza",
        "idb.rb",
    )
    return _sub(
        text,
        r'(?m)^  sha256 "[0-9a-f]{64}"$',
        f'  sha256 "{wheel_sha}"',
        1,
        "the sha256",
        "idb.rb",
    )


def cellar_dsl(cellar):
    """`brew bottle --json` reports symbolic cellars without the leading
    colon (observed live: "any_skip_relocation"); the formula DSL needs them
    as symbols — a string cellar means a literal cellar path and makes the
    bottle silently unpourable everywhere."""
    text = str(cellar)
    if text.lstrip(":") in ("any", "any_skip_relocation"):
        return f":{text.lstrip(':')}"
    return f'"{text}"'


def bottle_block_lines(bottle):
    """Render a formula `bottle do` block (2-space base indent) from one
    entry of `brew bottle --json` output. Values come from the JSON only."""
    lines = ["  bottle do", f'    root_url "{bottle["root_url"]}"']
    if bottle.get("rebuild"):
        lines.append(f"    rebuild {bottle['rebuild']}")
    for tag_name, tag_info in bottle["tags"].items():
        cellar = tag_info.get("cellar", bottle.get("cellar"))
        sha = tag_info["sha256"]
        if cellar is None:
            lines.append(f'    sha256 {tag_name}: "{sha}"')
        else:
            lines.append(
                f'    sha256 cellar: {cellar_dsl(cellar)}, {tag_name}: "{sha}"'
            )
    lines.append("  end")
    return "\n".join(lines)


def bottle_blocks_from_dir(directory):
    blocks = {}
    for path in sorted(Path(directory).glob("*.bottle.json")):
        for name, entry in json.loads(path.read_text()).items():
            blocks[name.split("/")[-1] + ".rb"] = bottle_block_lines(entry["bottle"])
    if not blocks:
        raise FormulaError("the bottle-json artifact contains no *.bottle.json files")
    return blocks


def insert_bottle_block(text, block, name):
    existing = re.search(r"(?ms)^  bottle do\n.*?\n  end\n", text)
    if existing:
        return text[: existing.start()] + block + "\n" + text[existing.end() :]
    new, count = re.subn(
        r'(?m)^  license "[^"]+"$',
        lambda match: f"{match.group(0)}\n\n{block}\n",
        text,
    )
    if count != 1:
        raise FormulaError(
            f"{name}: expected 1 match for the license line to place the "
            f"bottle block after, found {count}"
        )
    return new.replace("  end\n\n\n", "  end\n\n")
