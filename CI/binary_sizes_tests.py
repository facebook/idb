# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The size report, over Mach-O images and archives built byte by byte."""

from __future__ import annotations

import os
import struct
import tempfile
import unittest
from pathlib import Path

from . import binary_sizes

MH_EXECUTE = 0x2
MH_OBJECT = 0x1


def macho(
    filetype: int,
    sections: list[tuple[str, str, int, int]],
    symbols: list[tuple[str, int, int]] = (),
) -> bytes:
    """A 64-bit arm64 image with one segment per section, then a symbol table.

    `sections` are (segment, section, address, size); `symbols` are (name,
    1-based section index, address).
    """
    commands = b""
    for segment, section, address, size in sections:
        header = struct.pack(
            "<II16sQQQQiiII",
            0x19,
            72 + 80,
            segment.encode(),
            address,
            size,
            0,
            0,
            7,
            7,
            1,
            0,
        )
        entry = struct.pack(
            "<16s16sQQIIIIIIII",
            section.encode(),
            segment.encode(),
            address,
            size,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
        )
        commands += header + entry
    strings = b"\0"
    table = b""
    for name, section_index, address in symbols:
        table += struct.pack("<IBBHQ", len(strings), 0x0F, section_index, 0, address)
        strings += name.encode() + b"\0"
    symoff = 32 + len(commands) + 24
    commands += struct.pack(
        "<IIIIII", 0x2, 24, symoff, len(symbols), symoff + len(table), len(strings)
    )
    header = struct.pack(
        "<IiiIIIII",
        0xFEEDFACF,
        0x0100000C,
        0,
        filetype,
        len(sections) + 1,
        len(commands),
        0,
        0,
    )
    return header + commands + table + strings


def archive(members: list[tuple[str, bytes]]) -> bytes:
    data = b"!<arch>\n"
    for name, body in members:
        if len(name) > 16:
            body = name.encode() + body
            name = f"#1/{len(name)}"
        data += (
            f"{name:<16}{0:<12}{0:<6}{0:<6}{644:<8}{len(body):<10}`\n".encode() + body
        )
        if len(body) % 2:
            data += b"\n"
    return data


def universal(slices: list[tuple[int, bytes]]) -> bytes:
    header = struct.pack(">II", 0xCAFEBABE, len(slices))
    offset = 8 + 20 * len(slices)
    entries = b""
    bodies = b""
    for cputype, body in slices:
        entries += struct.pack(">iiIII", cputype, 0, offset + len(bodies), len(body), 0)
        bodies += body
    return header + entries + bodies


EXECUTABLE = macho(
    MH_EXECUTE,
    [("__TEXT", "__text", 0x1000, 0x100), ("__DWARF", "__debug_info", 0, 0x5000)],
    [
        ("_$s18FBSimulatorControl9SimulatorC4bootyyF", 1, 0x1000),
        ("_$s7NIOCore10ByteBufferV4readyyF", 1, 0x1040),
        ("_main", 1, 0x10C0),
    ],
)


class BinarySizesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, relative: str, data: bytes) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def test_a_linked_image_is_attributed_to_the_modules_of_its_symbols(self) -> None:
        product = binary_sizes.measure(
            self.write("idb_companion", EXECUTABLE), "idb_companion"
        )
        assert product is not None
        self.assertEqual(product.kind, "executable")
        self.assertEqual(product.code_and_data, 0x100)
        self.assertEqual(
            product.modules,
            {"FBSimulatorControl": 0x40, "NIOCore": 0x80, "everything else": 0x40},
        )

    def test_a_static_library_counts_its_objects_and_leaves_out_their_debug_info(
        self,
    ) -> None:
        member = macho(
            MH_OBJECT,
            [("__TEXT", "__text", 0, 100), ("__DWARF", "__debug_info", 0, 1000)],
        )
        path = self.write(
            "libFBSimulatorControl.a",
            archive(
                [
                    ("__.SYMDEF SORTED", b"\0" * 8),
                    ("Simulator.o", member),
                    ("SimulatorBootStrategy.swift.o", member),
                ]
            ),
        )
        product = binary_sizes.measure(path, path.name)
        assert product is not None
        self.assertEqual(product.kind, "static library (2 objects)")
        self.assertEqual(product.code_and_data, 200)
        self.assertEqual(product.modules, {})

    def test_a_universal_binary_is_measured_by_its_arm64_slice(self) -> None:
        x86 = macho(MH_EXECUTE, [("__TEXT", "__text", 0, 9999)])
        path = self.write(
            "tool", universal([(0x01000007, x86), (0x0100000C, EXECUTABLE)])
        )
        product = binary_sizes.measure(path, path.name)
        assert product is not None
        self.assertEqual(product.code_and_data, 0x100)

    def test_collection_skips_debug_symbols_test_bundles_links_and_other_files(
        self,
    ) -> None:
        self.write("Distribution/idb_companion", EXECUTABLE)
        self.write(
            "Distribution/Resources/IDBAPI.swiftinterface",
            b"// swift-interface-format-version: 1.0\n",
        )
        self.write(
            "Distribution/idb_companion.dSYM/Contents/Resources/DWARF/idb_companion",
            EXECUTABLE,
        )
        self.write("Distribution/Fixture.xctest/Contents/MacOS/Fixture", EXECUTABLE)
        os.symlink("idb_companion", self.root / "Distribution/companion-link")
        products = binary_sizes.collect([self.root / "Distribution"])
        self.assertEqual([p.path for p in products], ["idb_companion"])

    def test_the_module_table_names_every_own_module_and_folds_small_others(
        self,
    ) -> None:
        listed = binary_sizes.listed_modules(
            {
                "FBSimulatorControl": 5,
                "NIOCore": 900,
                "TinyDependency": 1,
                "everything else": 94,
            }
        )
        self.assertEqual(
            listed,
            [("NIOCore", 900), ("FBSimulatorControl", 5), ("everything else", 95)],
        )

    def test_the_report_is_a_table_of_products_then_each_image_by_module(self) -> None:
        self.write("idb_companion", EXECUTABLE)
        report = binary_sizes.render("Distribution", binary_sizes.collect([self.root]))
        self.assertIn("## Binary sizes: Distribution", report)
        self.assertIn(
            f"| `idb_companion` | executable | {binary_sizes.human(len(EXECUTABLE))} | 256 B |",
            report,
        )
        self.assertIn("### `idb_companion` by module", report)
        self.assertIn("| FBSimulatorControl | 64 B | 25.0% |", report)

    def test_sizes_read_in_decimal_units(self) -> None:
        self.assertEqual(binary_sizes.human(512), "512 B")
        self.assertEqual(binary_sizes.human(28_011_303), "28.01 MB")
        self.assertEqual(binary_sizes.human(1_642_080), "1.64 MB")
        self.assertEqual(binary_sizes.human(45_300), "45.3 KB")


if __name__ == "__main__":
    unittest.main()
