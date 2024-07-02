#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

from idb.grpc.hid import (
    event_to_grpc,
    GrpcHIDButton,
    GrpcHIDDelay,
    GrpcHIDEvent,
    GrpcHIDKey,
    GrpcHIDPress,
    GrpcHIDPressAction,
    GrpcHIDSwipe,
    GrpcHIDTouch,
    GrpcPoint,
    HIDButton,
    HIDButtonType,
    HIDDelay,
    HIDDirection,
    HIDKey,
    HIDPress,
    HIDSwipe,
    HIDTouch,
    Point,
)
from idb.utils.testing import TestCase


class HidTests(TestCase):
    def test_press(self) -> None:
        actions = [
            HIDTouch(point=Point(x=1, y=2)),
            HIDButton(button=HIDButtonType.HOME),
            HIDKey(keycode=3),
        ]
        expected = [
            GrpcHIDPressAction(touch=GrpcHIDTouch(point=GrpcPoint(x=1, y=2))),
            GrpcHIDPressAction(button=GrpcHIDButton(button=GrpcHIDEvent.HOME)),
            GrpcHIDPressAction(key=GrpcHIDKey(keycode=3)),
        ]
        for action, expected in zip(actions, expected):
            self.assertEqual(
                event_to_grpc(HIDPress(action=action, direction=HIDDirection.UP)),
                GrpcHIDEvent(
                    press=GrpcHIDPress(action=expected, direction=GrpcHIDEvent.UP)
                ),
            )

    def test_swipe(self) -> None:
        deltas = [None, 5]
        for delta in deltas:
            self.assertEqual(
                event_to_grpc(
                    HIDSwipe(
                        start=Point(x=1, y=2),
                        end=Point(x=3, y=4),
                        delta=delta,
                        duration=0.5,
                    )
                ),
                GrpcHIDEvent(
                    swipe=GrpcHIDSwipe(
                        start=GrpcPoint(x=1, y=2),
                        end=GrpcPoint(x=3, y=4),
                        # pyre-ignore
                        delta=delta,
                        duration=0.5,
                    )
                ),
            )

    def test_delay(self) -> None:
        self.assertEqual(
            event_to_grpc(HIDDelay(duration=1)),
            GrpcHIDEvent(delay=GrpcHIDDelay(duration=1)),
        )
