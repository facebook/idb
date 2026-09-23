#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from __future__ import annotations

import base64
import json
import pkgutil
import unittest

from idb.grpc.idb_pb2 import ReplRequest, ReplResponse


class ReplContractTests(unittest.TestCase):
    def test_language_neutral_repl_transcript(self) -> None:
        fixture_data = pkgutil.get_data("idb.grpc.tests", "repl_transcript.v1.json")
        self.assertIsNotNone(fixture_data)
        fixture = json.loads(fixture_data)
        self.assertEqual(set(fixture), {"scope", "steps", "version"})
        self.assertEqual(fixture["version"], 1)
        self.assertEqual(fixture["scope"], "swift-protobuf-wire-contract")

        steps = fixture["steps"]
        self.assertEqual(
            [step["kind"] for step in steps],
            [
                "Start",
                "Ready",
                "Execute",
                "Result",
                "client_half_close",
                "Stopped",
            ],
        )

        message_types = {
            "Start": ReplRequest,
            "Ready": ReplResponse,
            "Execute": ReplRequest,
            "Result": ReplResponse,
            "Stopped": ReplResponse,
        }
        messages = {}
        for step in steps:
            kind = step["kind"]
            if kind == "client_half_close":
                self.assertEqual(step, {"kind": "client_half_close"})
                continue

            self.assertEqual(set(step), {"kind", "protobuf_base64"})
            payload = base64.b64decode(step["protobuf_base64"], validate=True)
            message = message_types[kind].FromString(payload)
            self.assertEqual(message.SerializeToString(), payload)
            messages[kind] = message

        start = messages["Start"]
        self.assertEqual(start.WhichOneof("control"), "start")
        self.assertEqual(start.start.test_bundle_path, "FixtureTests.xctest")
        self.assertEqual(start.start.context, ReplRequest.Start.TEST)
        self.assertEqual(start.start.probe_file_path, "/tmp/idb-repl-fixture-probe")

        ready = messages["Ready"]
        self.assertEqual(ready.WhichOneof("event"), "ready")
        self.assertEqual(ready.ready.device_type, "iphone")
        self.assertEqual(
            [
                (interface.module_name, interface.contents)
                for interface in ready.ready.generated_interfaces
            ],
            [("IDB", "public struct Fixture {}")],
        )
        self.assertEqual(ready.ready.os_version, "26.0")
        self.assertEqual(ready.ready.next_run_index, 0)
        self.assertTrue(ready.ready.shared_filesystem)
        self.assertEqual(ready.ready.session_id, "fixture-session")

        execute = messages["Execute"]
        self.assertEqual(execute.WhichOneof("control"), "execute")
        self.assertEqual(execute.execute.dylib, b"\xca\xfe")
        self.assertEqual(execute.execute.symbol, "idb_repl_0")

        result = messages["Result"]
        self.assertEqual(result.WhichOneof("event"), "result")
        self.assertTrue(result.result.success)
        self.assertEqual(result.result.output, "ok")
        self.assertEqual(result.result.next_run_index, 1)
        self.assertEqual(
            [
                (artifact.host_path, artifact.container_path)
                for artifact in result.result.artifacts
            ],
            [
                (
                    "/tmp/idb-repl-artifacts/fixture-session/capture.png",
                    "idb-repl-artifacts/fixture-session/capture.png",
                )
            ],
        )

        stopped = messages["Stopped"]
        self.assertEqual(stopped.WhichOneof("event"), "stopped")
        self.assertEqual(stopped.stopped.desc, "REPL session ended")
