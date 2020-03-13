#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import List, Tuple, TypeVar

from idb.common.types import (
    HIDButton,
    HIDButtonType,
    HIDDelay,
    HIDDirection,
    HIDEvent,
    HIDKey,
    HIDPress,
    HIDPressAction,
    HIDSwipe,
    HIDTouch,
    Point,
)
from idb.grpc.idb_pb2 import HIDEvent as GrpcHIDEvent, Point as GrpcPoint


GrpcHIDButton = GrpcHIDEvent.HIDButton
GrpcHIDDelay = GrpcHIDEvent.HIDDelay
GrpcHIDKey = GrpcHIDEvent.HIDKey
GrpcHIDPress = GrpcHIDEvent.HIDPress
GrpcHIDPressAction = GrpcHIDEvent.HIDPressAction
GrpcHIDSwipe = GrpcHIDEvent.HIDSwipe
GrpcHIDTouch = GrpcHIDEvent.HIDTouch
GrpcHIDButtonType = GrpcHIDEvent.HIDButtonType
GrpcHIDDirection = GrpcHIDEvent.HIDDirection
_A = TypeVar("_A")
_B = TypeVar("_B")


BUTTON_TYPE_PAIRS: "List[Tuple[HIDButtonType, GrpcHIDButtonType]]" = [
    (HIDButtonType.APPLE_PAY, GrpcHIDEvent.APPLE_PAY),
    (HIDButtonType.HOME, GrpcHIDEvent.HOME),
    (HIDButtonType.LOCK, GrpcHIDEvent.LOCK),
    (HIDButtonType.SIDE_BUTTON, GrpcHIDEvent.SIDE_BUTTON),
    (HIDButtonType.SIRI, GrpcHIDEvent.SIRI),
]

DIRECTION_PAIRS: "List[Tuple[HIDDirection, GrpcHIDDirection]]" = [
    (HIDDirection.DOWN, GrpcHIDEvent.DOWN),
    (HIDDirection.UP, GrpcHIDEvent.UP),
]


def _tanslation_from_pairs(pairs: List[Tuple[_A, _B]], item: _A) -> _B:
    pair_map = {py: grpc for (py, grpc) in pairs}
    return pair_map[item]


def button_type_to_grpc(button_type: HIDButtonType) -> GrpcHIDButtonType:
    return _tanslation_from_pairs(BUTTON_TYPE_PAIRS, button_type)


def direction_to_grpc(direction: HIDDirection) -> GrpcHIDDirection:
    return _tanslation_from_pairs(DIRECTION_PAIRS, direction)


def point_to_grpc(point: Point) -> GrpcPoint:
    return GrpcPoint(x=point.x, y=point.y)


def touch_to_grpc(touch: HIDTouch) -> GrpcHIDTouch:
    return GrpcHIDTouch(point=point_to_grpc(touch.point))


def button_to_grpc(button: HIDButton) -> GrpcHIDButton:
    return GrpcHIDButton(button=button_type_to_grpc(button.button))


def key_to_grpc(key: HIDKey) -> GrpcHIDKey:
    return GrpcHIDKey(keycode=key.keycode)


def press_action_to_grpc(action: HIDPressAction) -> GrpcHIDPressAction:
    if isinstance(action, HIDTouch):
        return GrpcHIDPressAction(touch=touch_to_grpc(action))
    elif isinstance(action, HIDButton):
        return GrpcHIDPressAction(button=button_to_grpc(action))
    elif isinstance(action, HIDKey):
        return GrpcHIDPressAction(key=key_to_grpc(action))
    else:
        raise Exception(f"Invalid press action {action}")


def press_to_grpc(press: HIDPress) -> GrpcHIDPress:
    return GrpcHIDPress(
        action=press_action_to_grpc(press.action),
        direction=direction_to_grpc(press.direction),
    )


def swipe_to_grpc(swipe: HIDSwipe) -> GrpcHIDSwipe:
    return GrpcHIDSwipe(
        start=point_to_grpc(swipe.start),
        end=point_to_grpc(swipe.end),
        delta=swipe.delta,
    )


def delay_to_grpc(delay: HIDDelay) -> GrpcHIDDelay:
    return GrpcHIDDelay(duration=delay.duration)


def event_to_grpc(event: HIDEvent) -> GrpcHIDEvent:
    if isinstance(event, HIDPress):
        return GrpcHIDEvent(press=press_to_grpc(event))
    elif isinstance(event, HIDSwipe):
        return GrpcHIDEvent(swipe=swipe_to_grpc(event))
    elif isinstance(event, HIDDelay):
        return GrpcHIDEvent(delay=delay_to_grpc(event))
    else:
        raise Exception(f"Invalid event {event}")
