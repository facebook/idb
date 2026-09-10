# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Moving files in and out of an installed application's container.

``--application`` names the container of application containers, in which each
installed app appears under its own bundle id, so every path here is prefixed
with the fixture app's. The deprecated ``--bundle-id`` says the same thing and
is not used.

What makes this worth a test is that the bytes make a round trip through the
companion twice, in opposite directions, and that both ends are observable:
what ``push`` wrote is read off the host filesystem through the container
simctl reports, and what ``pull`` brought back is compared with what went in.
An `ls` that agrees with an empty directory proves nothing, so it is checked
against ground truth rather than against itself.
"""

from __future__ import annotations

from .harness import IdbEndToEndTestCase

# Under Documents, which every application has and nothing else writes to.
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
