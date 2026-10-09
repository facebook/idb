# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Report the size of every binary a build produced, as Markdown.

Every Mach-O image and static library under the given paths gets a row with
its file size and its code and data, which leaves out the debug information a
static library carries. A linked image (an executable, dylib or bundle) also
gets its bytes attributed to the Swift module each symbol belongs to, which is
how a library linked statically into it, such as FBSimulatorControl into
idb_companion, is measured.

Stdlib only: CI runs it with the runner's own python3.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
from collections import Counter, defaultdict
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
AR_MAGIC = b"!<arch>\n"
CPU_TYPE_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_SYMTAB = 0x2
N_STAB = 0xE0
N_TYPE = 0x0E
N_SECT = 0x0E
LINKED_FILETYPES = {0x2: "executable", 0x6: "dylib", 0x8: "bundle"}

# Debug information and linker metadata, which a static library carries and a
# stripped product does not; the rest is the code and data the product ships.
NOT_SHIPPED_SEGMENTS = frozenset({"__DWARF", "__LD", "__LINKEDIT", "__PAGEZERO"})

# Directories whose Mach-O files are not products: debug symbols and test bundles.
SKIPPED_DIRECTORY_SUFFIXES = (".dSYM", ".xctest", ".swiftmodule")

SWIFT_SYMBOL = re.compile(r"^_?\$[sS](\d+)")

# Modules this project owns, which a module table always lists by name.
OWN_MODULE_PREFIXES = ("FB", "IDB", "Companion", "Simulator", "Repl", "Shimulator")
# Below this share of an image, a module nobody here owns joins "everything else".
MINIMUM_LISTED_SHARE = 0.01


@dataclass
class Section:
    segment: str
    name: str
    address: int
    size: int


@dataclass
class Image:
    filetype: int
    sections: list[Section]
    # (address, name, 1-based section index) for each defined section symbol.
    symbols: list[tuple[int, str, int]]

    @property
    def code_and_data(self) -> int:
        return sum(
            s.size for s in self.sections if s.segment not in NOT_SHIPPED_SEGMENTS
        )


@dataclass
class Product:
    path: str
    kind: str
    file_size: int
    code_and_data: int
    modules: dict[str, int] = field(default_factory=dict)


def thin(data: bytes) -> bytes:
    """The arm64 slice of a universal binary, or `data` itself."""
    if len(data) < 8 or struct.unpack_from(">I", data, 0)[0] != FAT_MAGIC:
        return data
    (count,) = struct.unpack_from(">I", data, 4)
    for index in range(count):
        cputype, _, offset, size, _ = struct.unpack_from(">iiIII", data, 8 + index * 20)
        if cputype == CPU_TYPE_ARM64:
            return data[offset : offset + size]
    raise ValueError("no arm64 slice")


def parse_image(data: bytes) -> Image | None:
    data = thin(data)
    if len(data) < 32 or struct.unpack_from("<I", data, 0)[0] != MH_MAGIC_64:
        return None
    _, _, _, filetype, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    sections: list[Section] = []
    symtab = None
    offset = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, offset)
        if cmd == LC_SEGMENT_64:
            (nsects,) = struct.unpack_from("<I", data, offset + 64)
            for index in range(nsects):
                base = offset + 72 + index * 80
                name = data[base : base + 16].rstrip(b"\0").decode()
                segment = data[base + 16 : base + 32].rstrip(b"\0").decode()
                address, size = struct.unpack_from("<QQ", data, base + 32)
                sections.append(Section(segment, name, address, size))
        elif cmd == LC_SYMTAB:
            symtab = struct.unpack_from("<IIII", data, offset + 8)
        offset += cmdsize
    symbols: list[tuple[int, str, int]] = []
    if symtab is not None:
        symoff, nsyms, stroff, _ = symtab
        for index in range(nsyms):
            strx, ntype, nsect, _, value = struct.unpack_from(
                "<IBBHQ", data, symoff + index * 16
            )
            if (
                ntype & N_STAB
                or (ntype & N_TYPE) != N_SECT
                or not 0 < nsect <= len(sections)
            ):
                continue
            end = data.index(b"\0", stroff + strx)
            symbols.append(
                (value, data[stroff + strx : end].decode("utf-8", "replace"), nsect)
            )
    return Image(filetype, sections, symbols)


def archive_members(data: bytes) -> Iterable[bytes]:
    """The members of a BSD or System V `ar` archive, without its symbol table."""
    offset = len(AR_MAGIC)
    while offset + 60 <= len(data):
        header = data[offset : offset + 60]
        name = header[:16].decode("ascii", "replace").strip()
        size = int(header[48:58].decode("ascii").strip())
        body = data[offset + 60 : offset + 60 + size]
        if name.startswith("#1/"):
            name_length = int(name[3:])
            name = body[:name_length].rstrip(b"\0").decode("utf-8", "replace")
            body = body[name_length:]
        if not name.startswith(("__.SYMDEF", "/")):
            yield body
        offset += 60 + size + (size % 2)


def module_of(symbol: str) -> str:
    match = SWIFT_SYMBOL.match(symbol)
    if match:
        start = match.end()
        return symbol[start : start + int(match.group(1))]
    if symbol.startswith(("-[", "+[", "_OBJC_", "__OBJC_")):
        return "Objective-C"
    return "everything else"


def attribute(image: Image) -> dict[str, int]:
    """Each defined symbol's bytes, to the next symbol in its section or the section's end."""
    by_section: dict[int, list[tuple[int, str]]] = defaultdict(list)
    for address, name, section in image.symbols:
        by_section[section].append((address, name))
    totals: Counter[str] = Counter()
    for index, symbols in by_section.items():
        section = image.sections[index - 1]
        if section.segment in NOT_SHIPPED_SEGMENTS:
            continue
        symbols.sort()
        # Aliases share an address; the first name takes the bytes.
        distinct = [
            s for i, s in enumerate(symbols) if i == 0 or symbols[i - 1][0] != s[0]
        ]
        for position, (address, name) in enumerate(distinct):
            end = (
                distinct[position + 1][0]
                if position + 1 < len(distinct)
                else section.address + section.size
            )
            totals[module_of(name)] += max(0, end - address)
    return dict(totals)


def measure(path: Path, relative: str) -> Product | None:
    data = path.read_bytes()
    if data.startswith(AR_MAGIC):
        objects = [image for image in map(parse_image, archive_members(data)) if image]
        return Product(
            relative,
            f"static library ({len(objects)} objects)",
            len(data),
            sum(o.code_and_data for o in objects),
        )
    image = parse_image(data)
    if image is None:
        return None
    kind = LINKED_FILETYPES.get(image.filetype, "object")
    modules = attribute(image) if image.filetype in LINKED_FILETYPES else {}
    return Product(relative, kind, len(data), image.code_and_data, modules)


def collect(roots: Sequence[Path]) -> list[Product]:
    products: list[Product] = []
    for root in roots:
        if root.is_file():
            product = measure(root, root.name)
            if product:
                products.append(product)
            continue
        for directory, subdirectories, files in os.walk(root):
            subdirectories[:] = sorted(
                d for d in subdirectories if not d.endswith(SKIPPED_DIRECTORY_SUFFIXES)
            )
            for name in sorted(files):
                path = Path(directory) / name
                # A framework's Versions/Current links would count its binary twice.
                if path.is_symlink():
                    continue
                product = measure(path, str(path.relative_to(root)))
                if product:
                    products.append(product)
    return products


def human(size: int) -> str:
    if size >= 1_000_000:
        return f"{size / 1_000_000:.2f} MB"
    if size >= 1_000:
        return f"{size / 1_000:.1f} KB"
    return f"{size} B"


def listed_modules(modules: dict[str, int]) -> list[tuple[str, int]]:
    """Every module this project owns, and any other above the minimum share, largest first,
    with the rest folded into one row."""
    total = sum(modules.values())
    listed: list[tuple[str, int]] = []
    rest = 0
    for name, size in sorted(modules.items(), key=lambda item: (-item[1], item[0])):
        if name != "everything else" and (
            name.startswith(OWN_MODULE_PREFIXES) or size >= total * MINIMUM_LISTED_SHARE
        ):
            listed.append((name, size))
        else:
            rest += size
    if rest:
        listed.append(("everything else", rest))
    return listed


def render(title: str, products: Sequence[Product]) -> str:
    lines = [f"## Binary sizes: {title}", ""]
    if not products:
        return "\n".join(lines + ["No binaries found.", ""])
    lines += ["| Product | Kind | File | Code and data |", "|---|---|---:|---:|"]
    for product in products:
        lines.append(
            f"| `{product.path}` | {product.kind} | {human(product.file_size)} | {human(product.code_and_data)} |"
        )
    for product in products:
        if not product.modules:
            continue
        total = sum(product.modules.values())
        lines += [
            "",
            f"### `{product.path}` by module",
            "",
            "| Module | Size | Share |",
            "|---|---:|---:|",
        ]
        for name, size in listed_modules(product.modules):
            lines.append(f"| {name} | {human(size)} | {size / total:.1%} |")
    return "\n".join(lines + [""])


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--title", required=True, help="what was built, for the report's heading"
    )
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="binaries, or directories to search for them",
    )
    args = parser.parse_args(argv)
    print(render(args.title, collect(args.paths)))


if __name__ == "__main__":
    main()
