# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Profile a running application with each `idb profile` subcommand."""

from __future__ import annotations

import getpass
import json
import subprocess
from typing import Any

from .harness import IdbEndToEndTestCase

# Hosts that deny `task_for_pid`, so the inspecting tools cannot read the
# process. Nothing the companion does can work around these.
INSPECTION_HOST_LIMITATIONS = ("_dyld_process_info_create() failed",)

# xctrace on hosts that cannot record: without the privilege to raise its own
# scheduling priority, or against a custom device set it cannot see.
TRACE_HOST_LIMITATIONS = (
    "Could not set the recording priority",
    "shimMissing",
    "No devices found matching",
)

PROCESS_NAME = "ReplHost"


def developer_tools_access() -> str:
    """The host state that decides whether the simulator runtime's tools, which
    carry no task-port entitlement, may inspect another process."""
    commands = (
        ["DevToolsSecurity", "-status"],
        ["dseditgroup", "-o", "checkmember", "-m", getpass.getuser(), "_developer"],
    )
    lines = []
    for command in commands:
        try:
            completed = subprocess.run(
                command, capture_output=True, text=True, timeout=10
            )
            output = (completed.stdout + completed.stderr).strip()
        except (OSError, subprocess.TimeoutExpired) as error:
            output = str(error)
        lines.append(f"{' '.join(command)}: {output}")
    return "; ".join(lines)


class ProfileTests(IdbEndToEndTestCase):
    async def asyncSetUp(self) -> None:
        await super().asyncSetUp()
        self.bundle_id = await self.install_fixture_app()
        self.addAsyncCleanup(self.terminate_quietly, self.bundle_id)
        await self.idb("launch", self.bundle_id)

    async def profile(self, kind: str, *args: str) -> Any:
        completed = await self.idb(
            "profile",
            kind,
            "--bundle-id",
            self.bundle_id,
            *args,
            "--json",
            check=False,
        )
        if completed.returncode != 0:
            self.skip_on_host_limitation(
                f"profile {kind}", completed.error_text, INSPECTION_HOST_LIMITATIONS
            )
        return json.loads(completed.text)

    def skip_on_host_limitation(
        self, command: str, error_text: str, limitations: tuple[str, ...]
    ) -> None:
        limitation = next((m for m in limitations if m in error_text), None)
        if limitation is None:
            self.fail(f"{command} failed: {error_text}")
        self.skipTest(
            f"{command} cannot run on this host: {limitation} ({developer_tools_access()})"
        )

    def assert_profiled_the_fixture(self, process: dict[str, Any]) -> None:
        # Tools that cannot read the image list name the process by executable.
        self.assertIn(process["identifier"], (self.bundle_id, PROCESS_NAME))
        self.assertGreater(process["pid"], 0)
        self.assertGreater(process["physicalFootprintBytes"], 0)

    async def test_leaks_reports_the_leaked_allocations(self) -> None:
        report = (await self.profile("leaks"))["leaks"]

        self.assert_profiled_the_fixture(report["process"])
        self.assertGreaterEqual(report["leakCount"], 0)
        self.assertEqual(len(report["groups"]) > 0, report["leakCount"] > 0)

    async def test_heap_reports_live_allocations_by_class(self) -> None:
        report = (await self.profile("heap"))["heap"]

        self.assert_profiled_the_fixture(report["process"])
        self.assertGreater(report["nodeCount"], 0)
        self.assertGreater(report["bytes"], 0)
        self.assertTrue(report["classes"], "heap reported no classes")

    async def test_vmmap_reports_regions_and_their_total(self) -> None:
        report = (await self.profile("vmmap"))["vmmap"]

        self.assert_profiled_the_fixture(report["process"])
        self.assertTrue(report["regions"], "vmmap reported no regions")
        self.assertGreater(report["total"]["virtualBytes"], 0)
        self.assertGreater(report["total"]["residentBytes"], 0)

    async def test_footprint_reports_categories(self) -> None:
        report = (await self.profile("footprint"))["footprint"]

        self.assertGreater(report["pid"], 0)
        self.assertGreater(report["footprintBytes"], 0)
        self.assertGreaterEqual(report["peakFootprintBytes"], report["footprintBytes"])
        self.assertTrue(report["categories"], "footprint reported no categories")

    async def test_sample_reports_every_thread(self) -> None:
        report = (await self.profile("sample", "--duration", "1"))["sample"]

        self.assert_profiled_the_fixture(report["process"])
        self.assertGreater(report["totalSamples"], 0)
        # Without the image list, sample names the main thread "Thread_N: Main Thread".
        self.assertRegex(
            " ".join(thread["name"] for thread in report["threads"]),
            r"(?i)main[- ]thread",
        )

    async def test_memgraph_writes_the_graph_to_the_output_path(self) -> None:
        destination = self.make_temporary_directory() / "fixture.memgraph"

        report = (await self.profile("memgraph", "--output", str(destination)))["leaks"]

        self.assert_profiled_the_fixture(report["process"])
        self.assertGreater(destination.stat().st_size, 0)

    async def test_resources_streams_one_sample_per_interval(self) -> None:
        samples = await self.idb_json_lines(
            "profile",
            "resources",
            "--bundle-id",
            self.bundle_id,
            "--duration",
            "2",
            "--interval-ms",
            "500",
        )

        self.assertGreaterEqual(len(samples), 3, samples)
        self.assertEqual({sample["processName"] for sample in samples}, {PROCESS_NAME})
        elapsed = [sample["elapsedMs"] for sample in samples]
        self.assertEqual(elapsed, sorted(elapsed))
        self.assertTrue(all(sample["footprintBytes"] > 0 for sample in samples))

    async def test_profiling_an_application_that_is_not_running_fails(self) -> None:
        await self.terminate_quietly(self.bundle_id)

        await self.idb_expect_failure(
            "profile",
            "leaks",
            "--bundle-id",
            self.bundle_id,
            expected_error="No Matching processes",
        )

    async def test_trace_exports_the_time_profile(self) -> None:
        completed = await self.idb(
            "profile",
            "trace",
            "--bundle-id",
            self.bundle_id,
            "--duration",
            "3",
            "--json",
            check=False,
        )
        if completed.returncode != 0:
            self.skip_on_host_limitation(
                "profile trace", completed.error_text, TRACE_HOST_LIMITATIONS
            )

        report = json.loads(completed.text)["trace"]
        self.assertTrue(report["tables"], "trace exported no tables")
