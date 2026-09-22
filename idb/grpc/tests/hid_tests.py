#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from collections.abc import AsyncIterator
from unittest.mock import AsyncMock, call, MagicMock

from idb.common.types import HIDEvent
from idb.grpc.client import Client
from idb.grpc.hid import (
    event_to_grpc,
    GrpcHIDButton,
    GrpcHIDDelay,
    GrpcHIDEvent,
    GrpcHIDHinge,
    GrpcHIDKey,
    GrpcHIDOrientation,
    GrpcHIDPinch,
    GrpcHIDPress,
    GrpcHIDPressAction,
    GrpcHIDShake,
    GrpcHIDSwipe,
    GrpcHIDTouch,
    GrpcPoint,
    HIDButton,
    HIDButtonType,
    HIDDelay,
    HIDDirection,
    HIDHinge,
    HIDKey,
    HIDOrientation,
    HIDOrientationType,
    HIDPinch,
    HIDPress,
    HIDShake,
    HIDSwipe,
    HIDTouch,
    Point,
)
from idb.grpc.idb_pb2 import HIDResponse
from idb.utils.testing import TestCase


class HidTests(TestCase):
    def test_hinge(self) -> None:
        for angle in [0, 90, 135.5, 180]:
            with self.subTest(angle=angle):
                self.assertEqual(
                    event_to_grpc(HIDHinge(angle=angle)),
                    GrpcHIDEvent(hinge=GrpcHIDHinge(angle=angle)),
                )

    def test_hinge_rejects_invalid_angles(self) -> None:
        for angle in [-1, 180.001, float("nan"), float("inf"), -float("inf")]:
            with self.subTest(angle=angle), self.assertRaises(ValueError):
                HIDHinge(angle=angle)

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

    async def test_all_event_variants_stream_in_order_and_half_close(
        self,
    ) -> None:
        cases: list[tuple[HIDEvent, GrpcHIDEvent]] = [
            (
                HIDPress(
                    action=HIDTouch(point=Point(x=1, y=2)),
                    direction=HIDDirection.DOWN,
                ),
                GrpcHIDEvent(
                    press=GrpcHIDPress(
                        action=GrpcHIDPressAction(
                            touch=GrpcHIDTouch(point=GrpcPoint(x=1, y=2))
                        ),
                        direction=GrpcHIDEvent.DOWN,
                    )
                ),
            ),
            (
                HIDPress(
                    action=HIDButton(button=HIDButtonType.HOME),
                    direction=HIDDirection.UP,
                ),
                GrpcHIDEvent(
                    press=GrpcHIDPress(
                        action=GrpcHIDPressAction(
                            button=GrpcHIDButton(button=GrpcHIDEvent.HOME)
                        ),
                        direction=GrpcHIDEvent.UP,
                    )
                ),
            ),
            (
                HIDPress(
                    action=HIDKey(keycode=3),
                    direction=HIDDirection.DOWN,
                ),
                GrpcHIDEvent(
                    press=GrpcHIDPress(
                        action=GrpcHIDPressAction(key=GrpcHIDKey(keycode=3)),
                        direction=GrpcHIDEvent.DOWN,
                    )
                ),
            ),
            (
                HIDSwipe(
                    start=Point(x=4, y=5),
                    end=Point(x=6, y=7),
                    delta=8,
                    duration=0.5,
                ),
                GrpcHIDEvent(
                    swipe=GrpcHIDSwipe(
                        start=GrpcPoint(x=4, y=5),
                        end=GrpcPoint(x=6, y=7),
                        delta=8,
                        duration=0.5,
                    )
                ),
            ),
            (
                HIDDelay(duration=1.25),
                GrpcHIDEvent(delay=GrpcHIDDelay(duration=1.25)),
            ),
            (
                HIDPinch(
                    center=Point(x=9, y=10),
                    scale=1.5,
                    duration=0.75,
                    radius=40,
                ),
                GrpcHIDEvent(
                    pinch=GrpcHIDPinch(
                        center=GrpcPoint(x=9, y=10),
                        scale=1.5,
                        duration=0.75,
                        radius=40,
                    )
                ),
            ),
            (
                HIDOrientation(orientation=HIDOrientationType.LANDSCAPE_LEFT),
                GrpcHIDEvent(
                    orientation=GrpcHIDOrientation(
                        orientation=GrpcHIDEvent.LANDSCAPE_LEFT
                    )
                ),
            ),
            (HIDShake(), GrpcHIDEvent(shake=GrpcHIDShake())),
        ]

        stream = AsyncMock()
        stream.__aenter__.return_value = stream
        stream.__aexit__.return_value = None
        stream.recv_message.side_effect = [HIDResponse(), None]

        client = Client.__new__(Client)
        client.logger = MagicMock()
        client.stub = MagicMock()
        client.stub.hid.open.return_value = stream

        async def events() -> AsyncIterator[HIDEvent]:
            for event, _ in cases:
                yield event

        await client.hid(events())

        expected_requests = [request for _, request in cases]
        client.stub.hid.open.assert_called_once_with()
        stream.__aenter__.assert_awaited_once_with()
        stream.__aexit__.assert_awaited_once_with(None, None, None)
        self.assertEqual(
            stream.method_calls,
            [
                *[call.send_message(request) for request in expected_requests],
                call.end(),
                call.recv_message(),
                call.recv_message(),
            ],
        )
        stream.send_message.assert_has_awaits(
            [call(request) for request in expected_requests],
            any_order=False,
        )
        self.assertEqual(stream.send_message.await_count, len(expected_requests))
        stream.end.assert_awaited_once_with()
        self.assertEqual(stream.recv_message.await_count, 2)
