# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Test file transfers in an app container, checking bytes on the host.

With --application, paths start with the app bundle ID. simctl locates the
container so pushed files can be checked independently of idb.
"""

from __future__ import annotations

from .harness import IdbEndToEndTestCase

REMOTE_DIRECTORY = "Documents/idb-e2e"
FILE_NAME = "pushed.txt"
CONTENTS = b"idb end-to-end file transfer\n"


class FileTests(IdbEndToEndTestCase):
    async def test_file_round_trip_through_an_app_container(self) -> None:
        bundle_id = await self.install_fixture_app()
        container = await self.simctl.app_container(bundle_id)
        remote = f"{bundle_id}/{REMOTE_DIRECTORY}"
        on_disk = container / REMOTE_DIRECTORY

        local = self.make_temporary_directory()
        source = local / FILE_NAME
        source.write_bytes(CONTENTS)

        await self.idb("file", "mkdir", remote, "--application")
        self.assertTrue(on_disk.is_dir(), f"mkdir should have created {on_disk}")

        await self.idb("file", "push", str(source), remote, "--application")
        self.assertEqual(
            (on_disk / FILE_NAME).read_bytes(),
            CONTENTS,
            "push should have written the file into the app's container",
        )

        listed = await self.idb_json("file", "ls", remote, "--application")
        self.assertIn(FILE_NAME, [entry["path"] for entry in listed])

        destination = local / "pulled"
        destination.mkdir()
        await self.idb(
            "file",
            "pull",
            f"{remote}/{FILE_NAME}",
            str(destination),
            "--application",
        )
        self.assertEqual(
            (destination / FILE_NAME).read_bytes(),
            CONTENTS,
            "pull should have brought back what push sent",
        )

        await self.idb("file", "rm", remote, "--application")
        self.assertFalse(on_disk.exists(), f"rm should have removed {on_disk}")
        remaining = await self.idb_json(
            "file", "ls", f"{bundle_id}/Documents", "--application"
        )
        self.assertNotIn("idb-e2e", [entry["path"] for entry in remaining])
