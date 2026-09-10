# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Rewrite the facebook/homebrew-fb tap formulae for a facebook/idb release.

The single source for formula rewriting: the Release workflow's bottle job
uses it to bump a tap working copy to the release being cut before building
bottles from it, and the workflow's tap-formulae job uses `bump` (the CLI
below) to publish the finished formulae for that release as a run artifact,
which release tooling then copies into the tap's source of truth. Standard
library only, so it runs anywhere a python3 exists.

Every replacement is anchored and count-verified: if a formula's shape has
drifted from what the anchors expect, the rewrite raises FormulaError instead
of guessing, and nothing is modified.
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

COMPANION_URL_RE = (
    r'(?m)^  url "https://github\.com/facebook/idb/releases/download/v[^/"]+/'
    r'idb-companion\.macos-arm64\.tar\.gz"$'
)

# Anchored on the sha256 rather than the url, so the optional `version` stanza
# can be added or dropped without the region reaching back over the comments
# above it -- those belong to whoever wrote them, not to this rewriter.
COMPANION_VERSION_AND_SHA_RE = r'(?m)^(?:  version "[^"]+"\n)?  sha256 "[0-9a-f]{64}"$'


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


def rewrite_companion(text, tag, sha):
    version = version_from_tag(tag)
    text = _sub(
        text,
        COMPANION_URL_RE,
        f'  url "{_download_url(tag, COMPANION_ASSET)}"',
        1,
        "the companion tarball url",
        "idb-companion.rb",
    )
    stanza = f'  version "{version}"\n' if is_prerelease(version) else ""
    return _sub(
        text,
        COMPANION_VERSION_AND_SHA_RE,
        f'{stanza}  sha256 "{sha}"',
        1,
        "the version stanza and top-level sha256",
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


MANIFEST = "manifest.json"


def sha256_of_text(text):
    return hashlib.sha256(text.encode()).hexdigest()


def sha256_of_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_formulae(tap):
    return {name: (Path(tap) / name).read_text() for name in FORMULAE}


def bump_formulae(sources, tag, companion_sha, wheel_sha, bottle_blocks=None):
    """All three rewrites, plus the bottle blocks, computed before anything
    is returned: an anchor failure in any file yields nothing at all."""
    outputs = {
        "idb-companion.rb": rewrite_companion(
            sources["idb-companion.rb"], tag, companion_sha
        ),
        "idb-cli.rb": rewrite_cli(sources["idb-cli.rb"], tag, wheel_sha),
        "idb.rb": rewrite_idb(sources["idb.rb"], tag, wheel_sha),
    }
    for name, block in (bottle_blocks or {}).items():
        if name not in outputs:
            raise FormulaError(f"{name} is not a tap formula this tool rewrites")
        outputs[name] = insert_bottle_block(outputs[name], block, name)
    return outputs


def bump_manifest(tag, tap_commit, sources, outputs, companion_sha, wheel_sha):
    """What the artifact was computed from. `inputs` lets whoever applies the
    artifact check that the tap they are writing into is the tap it was made
    for, and `outputs` lets them check the files arrived intact."""
    return {
        "tag": tag,
        "tap_commit": tap_commit,
        "companion_sha256": companion_sha,
        "wheel_sha256": wheel_sha,
        "inputs": {name: sha256_of_text(text) for name, text in sources.items()},
        "outputs": {name: sha256_of_text(text) for name, text in outputs.items()},
    }


def write_bump(out_dir, outputs, manifest):
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
    write_bump(args.out, outputs, manifest)
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


def cmd_bump(args):
    sources = read_formulae(args.tap)
    companion_sha = sha256_of_file(_single_glob(args.companion, "companion tarball"))
    wheel_sha = sha256_of_file(_single_glob(args.wheel, "wheel"))
    blocks = bottle_blocks_from_dir(args.bottles) if args.bottles else None
    outputs = bump_formulae(sources, args.tag, companion_sha, wheel_sha, blocks)
    manifest = bump_manifest(
        args.tag, args.tap_commit, sources, outputs, companion_sha, wheel_sha
    )
    write_bump(args.out, outputs, manifest)
    for name in FORMULAE:
        state = "unchanged" if outputs[name] == sources[name] else "rewritten"
        print(f"{name}: {state}")
    print(f"wrote {len(outputs)} formulae and {MANIFEST} to {args.out}")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    bump = subparsers.add_parser(
        "bump",
        help="rewrite the tap formulae for a release into an output directory, "
        "with a manifest of what they were computed from",
    )
    bump.add_argument(
        "--tap", required=True, help="tap checkout to read the formulae from"
    )
    bump.add_argument("--tag", required=True, help="release tag, e.g. v1.5.4")
    bump.add_argument(
        "--companion", required=True, help="glob for the companion tarball asset"
    )
    bump.add_argument("--wheel", required=True, help="glob for the fb-idb wheel asset")
    bump.add_argument(
        "--bottles",
        help="directory of `brew bottle --json` output (omit for no bottle block)",
    )
    bump.add_argument(
        "--tap-commit",
        default="",
        help="commit of the tap checkout, recorded in the manifest",
    )
    bump.add_argument("--out", required=True, help="directory to write into")
    bump.set_defaults(func=cmd_bump)

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
