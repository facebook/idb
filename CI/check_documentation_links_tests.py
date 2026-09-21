# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from .check_documentation_links import broken_links, export_roots


def link(path: str, kind: str = "blob", ref: str = "main") -> str:
    return f"https://github.com/facebook/idb/{kind}/{ref}/{path}"


class CheckDocumentationLinksTest(unittest.TestCase):
    def setUp(self) -> None:
        self.monorepo = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.root = self.monorepo / "Source"
        self.write("Companion/main.swift", "")
        self.write("../fbcode/idb/cli/main.py", "")
        self.write("../xplat/idb/idb.proto", "")

    def write(self, path: str, text: str) -> Path:
        destination = self.root / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text)
        return destination

    def document(self, text: str, name: str = "website/docs/overview.mdx") -> None:
        self.write(name, text)

    def problems(self) -> list[str]:
        return broken_links(self.root)

    def test_accepts_a_link_to_a_file_that_exists(self) -> None:
        self.document(f"See [the entry point]({link('Companion/main.swift')}).")
        self.assertEqual(self.problems(), [])

    def test_reports_a_link_to_a_file_that_does_not_exist(self) -> None:
        self.document(f"See [the executor]({link('CompanionLib/Executor.swift')}).")
        self.assertEqual(
            self.problems(),
            [
                f"website/docs/overview.mdx: {link('CompanionLib/Executor.swift')} "
                "names CompanionLib/Executor.swift, which does not exist"
            ],
        )

    def test_accepts_a_directory_reached_through_tree(self) -> None:
        self.write("Shims/Shimulator/main.m", "")
        self.document(link("Shims/Shimulator", kind="tree"))
        self.assertEqual(self.problems(), [])

    def test_accepts_a_link_on_a_ref_other_than_main(self) -> None:
        self.document(link("Companion/main.swift", ref="v1.1.7"))
        self.assertEqual(self.problems(), [])

    def test_a_fragment_names_a_heading_or_lines_rather_than_a_file(self) -> None:
        self.document(link("Companion/main.swift") + "#L10-L20")
        self.assertEqual(self.problems(), [])

    def test_trailing_punctuation_belongs_to_the_sentence(self) -> None:
        self.document(f"It lives in {link('Companion/main.swift')}.")
        self.assertEqual(self.problems(), [])

    def test_ignores_urls_that_name_no_path_in_the_repository(self) -> None:
        self.document(
            "\n".join(
                [
                    "https://github.com/facebook/idb",
                    "https://github.com/facebook/idb/releases/tag/v1.1.7",
                    "https://github.com/facebook/idb/issues/999",
                ]
            )
        )
        self.assertEqual(self.problems(), [])

    def test_ignores_another_project_on_the_same_host(self) -> None:
        self.document("https://github.com/DeviceFarmer/minicap/blob/main/gone.cpp")
        self.assertEqual(self.problems(), [])

    def test_resolves_the_directories_exported_from_elsewhere(self) -> None:
        self.document(f"{link('idb/cli/main.py')} and {link('proto/idb.proto')}")
        self.assertEqual(self.problems(), [])

    def test_reports_those_directories_when_the_file_is_gone(self) -> None:
        (self.monorepo / "fbcode/idb/cli/main.py").unlink()
        self.document(link("idb/cli/main.py"))
        self.assertEqual(
            self.problems(),
            [
                f"website/docs/overview.mdx: {link('idb/cli/main.py')} "
                "names idb/cli/main.py, which does not exist"
            ],
        )

    def test_resolves_against_the_root_in_a_published_checkout(self) -> None:
        # A checkout of the published repository holds both prefixes itself, so
        # there is no ancestor to look in and every path is under the root.
        published = Path(self.enterContext(tempfile.TemporaryDirectory())) / "idb"
        published.mkdir()
        self.assertEqual(export_roots(published), (("", published),))

    def test_scans_markdown_beside_the_website(self) -> None:
        self.document(link("gone.swift"), name="FBDeviceControl/README.md")
        self.assertEqual(
            self.problems(),
            [
                f"FBDeviceControl/README.md: {link('gone.swift')} "
                "names gone.swift, which does not exist"
            ],
        )

    def test_skips_the_websites_dependencies_and_build_output(self) -> None:
        for directory in ("node_modules", "build", ".docusaurus"):
            self.document(link("gone.swift"), name=f"website/{directory}/README.md")
        self.assertEqual(self.problems(), [])
