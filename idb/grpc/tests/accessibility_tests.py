#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from idb.common.types import (
    AccessibilityBackend,
    AccessibilityElementFilter,
    AccessibilityInfoOptions,
    AccessibilityMarker,
    AccessibilityOutputFormat,
    AccessibilityPoint,
    AccessibilitySearchableKey,
    IdbException,
)
from idb.grpc.accessibility import accessibility_info_to_grpc
from idb.grpc.idb_pb2 import AccessibilityInfoRequest
from idb.utils.testing import TestCase


class AccessibilityInfoRequestTests(TestCase):
    # The historical request

    def test_default_options_are_a_legacy_whole_app_read(self) -> None:
        # Every new field is its zero value, so a caller who asks for nothing
        # sends what idb sent before any of them existed.
        self.assertEqual(
            accessibility_info_to_grpc(None, AccessibilityInfoOptions()),
            AccessibilityInfoRequest(),
        )

    def test_nested_flag_and_nested_format_agree(self) -> None:
        self.assertEqual(
            accessibility_info_to_grpc(None, AccessibilityInfoOptions(nested=True)),
            accessibility_info_to_grpc(
                None,
                AccessibilityInfoOptions(format=AccessibilityOutputFormat.NESTED),
            ),
        )

    def test_format_wins_over_the_deprecated_nested_flag(self) -> None:
        request = accessibility_info_to_grpc(
            None,
            AccessibilityInfoOptions(
                nested=True, format=AccessibilityOutputFormat.COMPLETE
            ),
        )
        self.assertEqual(request.format, AccessibilityInfoRequest.COMPLETE)

    # Targets

    def test_marker_target(self) -> None:
        request = accessibility_info_to_grpc(
            AccessibilityMarker(
                value="Login",
                match_key=AccessibilitySearchableKey.UNIQUE_ID,
                depth=4,
            ),
            AccessibilityInfoOptions(),
        )
        self.assertEqual(request.marker, "Login")
        self.assertEqual(request.match_key, AccessibilitySearchableKey.UNIQUE_ID.value)
        self.assertEqual(request.depth, 4)
        self.assertEqual(request.match, "")

    def test_point_target(self) -> None:
        request = accessibility_info_to_grpc(
            AccessibilityPoint(x=10, y=20), AccessibilityInfoOptions()
        )
        self.assertEqual(request.point.x, 10)
        self.assertEqual(request.point.y, 20)
        self.assertEqual(request.marker, "")

    # Match

    def test_match_sets_the_substring_and_its_key(self) -> None:
        request = accessibility_info_to_grpc(
            None,
            AccessibilityInfoOptions(
                match="Cart", match_key=AccessibilitySearchableKey.VALUE
            ),
        )
        self.assertEqual(request.match, "Cart")
        self.assertEqual(request.match_key, AccessibilitySearchableKey.VALUE.value)
        self.assertEqual(request.marker, "")

    def test_match_defaults_to_the_label(self) -> None:
        request = accessibility_info_to_grpc(
            None, AccessibilityInfoOptions(match="Cart")
        )
        self.assertEqual(request.match_key, AccessibilitySearchableKey.LABEL.value)

    def test_empty_match_is_no_match(self) -> None:
        # An empty substring is contained in everything, so treating it as a
        # match would send a predicate that keeps every element while looking
        # like a narrowing.
        request = accessibility_info_to_grpc(None, AccessibilityInfoOptions(match=""))
        self.assertEqual(request, AccessibilityInfoRequest())

    def test_match_with_a_marker_is_refused(self) -> None:
        with self.assertRaises(IdbException):
            accessibility_info_to_grpc(
                AccessibilityMarker(
                    value="Login",
                    match_key=AccessibilitySearchableKey.LABEL,
                    depth=10,
                ),
                AccessibilityInfoOptions(match="Cart"),
            )

    def test_match_with_a_point_is_refused(self) -> None:
        with self.assertRaises(IdbException):
            accessibility_info_to_grpc(
                AccessibilityPoint(x=1, y=2),
                AccessibilityInfoOptions(match="Cart"),
            )

    def test_ignore_case_is_independent_of_the_match(self) -> None:
        # --ignore-case also governs marker resolution on a read, so it is set
        # whether or not a match is present.
        request = accessibility_info_to_grpc(
            None, AccessibilityInfoOptions(ignore_case=True)
        )
        self.assertTrue(request.ignore_case)

    # Filter and backend

    def test_every_filter_maps(self) -> None:
        for element_filter, expected in [
            (AccessibilityElementFilter.ALL, AccessibilityInfoRequest.FILTER_ALL),
            (
                AccessibilityElementFilter.INTERACTABLE,
                AccessibilityInfoRequest.FILTER_INTERACTABLE,
            ),
        ]:
            request = accessibility_info_to_grpc(
                None, AccessibilityInfoOptions(filter=element_filter)
            )
            self.assertEqual(request.filter, expected)

    def test_unset_filter_is_the_wire_default(self) -> None:
        request = accessibility_info_to_grpc(None, AccessibilityInfoOptions())
        self.assertEqual(request.filter, AccessibilityInfoRequest.FILTER_ALL)

    def test_filter_and_match_compose(self) -> None:
        request = accessibility_info_to_grpc(
            None,
            AccessibilityInfoOptions(
                match="Cart",
                filter=AccessibilityElementFilter.INTERACTABLE,
                backend=AccessibilityBackend.AXBRIDGE,
            ),
        )
        self.assertEqual(request.match, "Cart")
        self.assertEqual(request.filter, AccessibilityInfoRequest.FILTER_INTERACTABLE)
        self.assertEqual(request.backend, AccessibilityInfoRequest.AXBRIDGE)
