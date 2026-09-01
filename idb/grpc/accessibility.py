#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from idb.common.types import (
    AccessibilityInfoOptions,
    AccessibilityMarker,
    AccessibilityPoint,
    AccessibilityTarget,
    IdbException,
)
from idb.grpc.idb_pb2 import AccessibilityInfoRequest


def accessibility_info_to_grpc(
    target: AccessibilityTarget | None,
    options: AccessibilityInfoOptions,
) -> AccessibilityInfoRequest:
    """The wire request for a read of `target` under `options`.

    Three targets and one option decide which elements come back: no target is
    the whole app, a point is the element under it, a marker is the single
    element that resolves, and `match` narrows the whole-app read to the
    elements whose `match_key` contains a substring.
    """
    if options.format is not None:
        wire_format = options.format.value
    elif options.nested:
        wire_format = AccessibilityInfoRequest.NESTED
    else:
        wire_format = AccessibilityInfoRequest.LEGACY
    request = AccessibilityInfoRequest(
        format=wire_format,
        keys=options.keys or [],
        profile=options.profile,
        collect_frame_coverage=options.collect_frame_coverage,
    )
    # Unset means "unspecified" on the wire: the companion's historical
    # default backend, and the only thing an older companion understands.
    if options.backend is not None:
        request.backend = options.backend.value
    if options.ignore_case:
        request.ignore_case = True
    if options.filter is not None:
        request.filter = options.filter.value
    # A match narrows the elements a whole-app read reports, so it is only
    # meaningful without a target. A marker read is the other verb — it selects
    # one element, and shares `match_key` with the match on the wire — and a
    # point read returns the one element under the point. Refusing here names
    # the caller's mistake rather than letting the companion's INVALID_ARGUMENT,
    # or a silently dropped field, do it.
    if options.match and target is not None:
        raise IdbException(
            "accessibility_info: match narrows a whole-app read, so it "
            f"cannot be combined with a {type(target).__name__} target"
        )
    if isinstance(target, AccessibilityMarker):
        request.marker = target.value
        request.match_key = target.match_key.value
        request.depth = target.depth
    elif isinstance(target, AccessibilityPoint):
        request.point.x = target.x
        request.point.y = target.y
    elif options.match:
        request.match = options.match
        request.match_key = options.match_key.value
    return request
