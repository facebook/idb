# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Render the facebook/homebrew-fb tap formulae for a facebook/idb release.

The templates in .github/formulae/ are the source of truth for the three idb
formulae; `render` turns them plus a release's inputs (tag, companion tarball,
wheel, optional `brew bottle --json` output) into the finished formulae and a
manifest. The Release workflow renders idb-cli.rb to bottle from, then renders
all three for publication; CI renders against locally built assets to install-
test them; release tooling copies the published render into the tap. Standard
library only, so it runs anywhere a python3 exists.
"""

from __future__ import annotations

import argparse
import glob
import hashlib
import json
import re
import string
import sys
from pathlib import Path

IDB_REPO = "facebook/idb"

COMPANION_ASSET = "idb-companion.macos-arm64.tar.gz"
FORMULAE = ("idb-companion.rb", "idb-cli.rb", "idb.rb")

TAG_RE = re.compile(r"^v\d+\.\d+\.\d+(?:\.(?:a|b|rc)\d+)?$")
PRERELEASE_RE = re.compile(r"\.(?:a|b|rc)\d+$")


class FormulaError(Exception):
    pass


def version_from_tag(tag):
    if not TAG_RE.match(tag):
        raise FormulaError(f"tag {tag!r} does not look like vX.Y.Z or vX.Y.Z.<a|b|rc>N")
    return tag[1:]


def is_prerelease(version):
    return PRERELEASE_RE.search(version) is not None


def pep440(version):
    # PyPI normalizes 1.5.0.b4 to 1.5.0b4; the wheel filename uses that form
    # while the formulae keep the release's own dotted form.
    return re.sub(r"\.((?:a|b|rc)\d+)$", r"\1", version)


def wheel_asset(version):
    return f"fb_idb-{pep440(version)}-py3-none-any.whl"


def companion_version(text):
    """The version idb-companion.rb currently declares. A prerelease carries an
    explicit stanza; a stable release carries the version only in its url."""
    match = re.search(r'(?m)^  version "([^"]+)"$', text)
    if match is not None:
        return match.group(1)
    match = re.search(
        r'(?m)^  url "https://github\.com/facebook/idb/releases/download/(v[^/"]+)/'
        r'idb-companion\.macos-arm64\.tar\.gz"$',
        text,
    )
    if match is None:
        raise FormulaError(
            "idb-companion.rb: neither a version stanza nor a companion tarball "
            "url — cannot tell what version this formula is on"
        )
    return version_from_tag(match.group(1))


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


MANIFEST = "manifest.json"


def sha256_of_text(text):
    return hashlib.sha256(text.encode()).hexdigest()


def sha256_of_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_rendered(out_dir, outputs, manifest):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for name, text in outputs.items():
        (out / name).write_text(text)
    (out / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


TEMPLATE_SUFFIX = ".in"


def default_templates_dir():
    """Source/.github/formulae, next to this script's directory."""
    return Path(__file__).resolve().parent.parent / "formulae"


def release_asset_base(tag):
    return f"https://github.com/{IDB_REPO}/releases/download/{tag}"


def generated_header(name, tag):
    return (
        f"# Rendered for {tag} from facebook/idb's "
        f"Source/.github/formulae/{name}{TEMPLATE_SUFFIX};\n"
        "# edit the template, not this file."
    )


def render_formulae(
    tag,
    companion_sha,
    wheel_sha,
    bottle_blocks=None,
    asset_base=None,
    templates_dir=None,
    only=None,
):
    """The three formulae for a release, from the templates alone: nothing
    here depends on what the tap currently contains. `asset_base` overrides
    the release download URL prefix, which is how CI points the formulae at
    freshly built local copies of the assets (file://...) to install-test
    them before any release exists. `only` restricts the set, e.g. the bottle
    job renders just idb-cli.rb before the companion tarball exists, in
    which case `companion_sha` may be None."""
    version = version_from_tag(tag)
    names = tuple(only) if only else FORMULAE
    unknown = sorted(set(names) - set(FORMULAE))
    if unknown:
        raise FormulaError(f"{', '.join(unknown)}: not a tap formula this tool renders")
    if "idb-companion.rb" in names and not companion_sha:
        raise FormulaError("idb-companion.rb needs the companion tarball's sha256")
    base = (asset_base or release_asset_base(tag)).rstrip("/")
    blocks = dict(bottle_blocks or {})
    unknown = sorted(set(blocks) - set(names))
    if unknown:
        raise FormulaError(f"{', '.join(unknown)}: not a tap formula this tool renders")
    directory = Path(templates_dir or default_templates_dir())
    values = {
        "tag": tag,
        "version": version,
        "companion_url": f"{base}/{COMPANION_ASSET}",
        "companion_sha256": companion_sha or "",
        "wheel_url": f"{base}/{wheel_asset(version)}",
        "wheel_sha256": wheel_sha,
        # Homebrew scans the version from the url on a stable tag; on a
        # prerelease the scan drops the suffix, so the stanza is needed.
        "companion_version_stanza": (
            f'  version "{version}"\n' if is_prerelease(version) else ""
        ),
    }
    outputs = {}
    for name in names:
        path = directory / f"{name}{TEMPLATE_SUFFIX}"
        if not path.exists():
            raise FormulaError(f"missing formula template {path}")
        block = blocks.get(name)
        per_file = dict(
            values,
            bottle_block=f"\n{block}\n" if block else "",
            generated_header=generated_header(name, tag),
        )
        try:
            outputs[name] = string.Template(path.read_text()).substitute(per_file)
        except (KeyError, ValueError) as error:
            raise FormulaError(f"{path.name}: bad placeholder {error}") from error
    return outputs


def render_manifest(tag, outputs, companion_sha, wheel_sha, asset_base):
    """What the rendered files were computed from, and their digests so
    whoever applies them can check they arrived intact."""
    return {
        "tag": tag,
        "asset_base": asset_base,
        "companion_sha256": companion_sha,
        "wheel_sha256": wheel_sha,
        "outputs": {name: sha256_of_text(text) for name, text in outputs.items()},
    }


def cmd_render(args):
    only = tuple(args.only) if args.only else FORMULAE
    if "idb-companion.rb" in only and not args.companion:
        raise FormulaError(
            "--companion is required unless --only leaves out idb-companion.rb"
        )
    companion_sha = (
        sha256_of_file(_single_glob(args.companion, "companion tarball"))
        if args.companion
        else None
    )
    wheel_sha = sha256_of_file(_single_glob(args.wheel, "wheel"))
    blocks = bottle_blocks_from_dir(args.bottles) if args.bottles else None
    asset_base = (args.asset_base or release_asset_base(args.tag)).rstrip("/")
    outputs = render_formulae(
        args.tag,
        companion_sha,
        wheel_sha,
        blocks,
        asset_base=asset_base,
        templates_dir=args.templates,
        only=only,
    )
    manifest = render_manifest(args.tag, outputs, companion_sha, wheel_sha, asset_base)
    write_rendered(args.out, outputs, manifest)
    for name in only:
        print(f"{name}: rendered")
    print(f"wrote {len(outputs)} formulae and {MANIFEST} to {args.out}")
    return 0


def _single_glob(pattern, what):
    matches = glob.glob(pattern)
    if len(matches) != 1:
        raise FormulaError(
            f"expected exactly one {what} matching {pattern!r}, found {matches}"
        )
    return matches[0]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser(
        "render",
        help="render the tap formulae for a release from the templates, "
        "independent of the tap's current contents",
    )
    render.add_argument("--tag", required=True, help="release tag, e.g. v1.5.4")
    render.add_argument(
        "--companion",
        help="glob for the companion tarball asset (required unless --only "
        "leaves out idb-companion.rb)",
    )
    render.add_argument(
        "--wheel", required=True, help="glob for the fb-idb wheel asset"
    )
    render.add_argument(
        "--only",
        action="append",
        choices=FORMULAE,
        help="render only this formula (repeatable; default: all three)",
    )
    render.add_argument(
        "--bottles",
        help="directory of `brew bottle --json` output (omit for no bottle block)",
    )
    render.add_argument(
        "--asset-base",
        help="URL prefix for the asset urls (default: the tag's GitHub release "
        "download directory; CI passes a file:// directory of local builds)",
    )
    render.add_argument(
        "--templates",
        help="directory holding the *.rb.in templates (default: Source/.github/formulae)",
    )
    render.add_argument("--out", required=True, help="directory to write into")
    render.set_defaults(func=cmd_render)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except FormulaError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
