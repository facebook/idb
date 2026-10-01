#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import enum
import importlib.util
import json
import sys
from collections.abc import Iterator
from contextlib import contextmanager
from types import ModuleType
from unittest import mock

from idb.common.types import (
    CompanionInfo,
    Compression,
    TargetDescription,
    TargetType,
    TCPAddress,
)
from idb.utils.testing import TestCase


@contextmanager
def _open_source_environment() -> Iterator[None]:
    # The client is published to pypi and installed onto interpreters that have
    # neither fbcode on the path, nor enum.StrEnum, which is python 3.11+. A None
    # entry in sys.modules makes importing that module raise ImportError.
    strenum = enum.StrEnum
    del enum.StrEnum
    try:
        with mock.patch.dict(sys.modules, {"python.migrations.py310": None}):
            yield
    finally:
        enum.StrEnum = strenum


def _reimport_types() -> ModuleType:
    # A fresh copy of the module is executed rather than reloaded, leaving the
    # idb.common.types that every other test imported untouched.
    spec = importlib.util.find_spec("idb.common.types")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TargetTypeTests(TestCase):
    def test_is_interchangeable_with_its_string_value(self) -> None:
        self.assertIsInstance(TargetType.SIMULATOR, str)
        self.assertEqual(TargetType.SIMULATOR, "simulator")
        self.assertEqual(TargetType("simulator"), TargetType.SIMULATOR)
        self.assertEqual(json.dumps({"type": TargetType.MAC}), '{"type": "mac"}')

    def test_formats_as_its_value(self) -> None:
        self.assertEqual(str(TargetType.DEVICE), "device")
        self.assertEqual(f"{TargetType.DEVICE}", "device")
        self.assertEqual(format(TargetType.MAC, ">6"), "   mac")

    def test_importable_outside_of_meta(self) -> None:
        with _open_source_environment():
            module = _reimport_types()
        self.assertEqual(
            [str(member) for member in module.TargetType],
            ["device", "simulator", "mac"],
        )


class TargetDescriptionTests(TestCase):
    def test_as_json_includes_the_companion(self) -> None:
        description = TargetDescription(
            udid="udid",
            name="iPhone",
            target_type=TargetType.SIMULATOR,
            state="Booted",
            os_version="iOS 18.0",
            architecture="arm64",
            companion_info=CompanionInfo(
                udid="udid",
                is_local=True,
                pid=None,
                address=TCPAddress(host="localhost", port=10882),
                supported_compressions=frozenset([Compression.ZSTD, Compression.GZIP]),
                zstd_zip_streams=True,
            ),
            screen_dimensions=None,
        )
        companion = json.loads(description.as_json)["companion_info"]
        self.assertEqual(companion["supported_compressions"], ["GZIP", "ZSTD"])
        self.assertTrue(companion["zstd_zip_streams"])
