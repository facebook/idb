#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import AsyncIterator, Dict, Iterable, List, Optional, Tuple

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


def tap_to_events(x: int, y: int, duration: Optional[float] = None) -> List[HIDEvent]:
    return _press_with_duration(HIDTouch(point=Point(x=x, y=y)), duration=duration)


def button_press_to_events(
    button: HIDButtonType, duration: Optional[float] = None
) -> List[HIDEvent]:
    return _press_with_duration(HIDButton(button=button), duration=duration)


def key_press_to_events(
    keycode: int, duration: Optional[float] = None
) -> List[HIDEvent]:
    return _press_with_duration(HIDKey(keycode=keycode), duration=duration)


def _press_with_duration(
    action: HIDPressAction, duration: Optional[float] = None
) -> List[HIDEvent]:
    events = []
    events.append(HIDPress(action=action, direction=HIDDirection.DOWN))
    if duration:
        events.append(HIDDelay(duration=duration))
    events.append(HIDPress(action=action, direction=HIDDirection.UP))
    return events


def swipe_to_events(
    p_start: Tuple[float, float],
    p_end: Tuple[float, float],
    duration: Optional[float] = None,
    delta: Optional[float] = None,
) -> List[HIDEvent]:
    if duration is None:
        start = Point(x=p_start[0], y=p_start[1])
        end = Point(x=p_end[0], y=p_end[1])
        return [HIDSwipe(start=start, end=end, delta=delta)]
    else:
        delta = 10.0 if delta is None else delta

        xStart, yStart = p_start
        xEnd, yEnd = p_end

        distance = ((xEnd - xStart) ** 2 + (yEnd - yStart) ** 2) ** 0.5
        steps = int(distance // delta)

        dx = (xEnd - xStart) / steps
        dy = (yEnd - yStart) / steps

        events = []
        for i in range(steps + 1):
            events.append(
                HIDPress(
                    action=HIDTouch(
                        point=Point(x=(xStart + i * dx), y=(yStart + i * dy))
                    ),
                    direction=HIDDirection.DOWN,
                )
            )
            if duration:
                events.append(HIDDelay(duration=(duration / (steps + 1))))

        events.append(
            HIDPress(
                action=HIDTouch(point=Point(x=xEnd, y=yEnd)), direction=HIDDirection.UP
            )
        )

        return events


def _key_down_event(keycode: int) -> HIDEvent:
    return HIDPress(action=HIDKey(keycode=keycode), direction=HIDDirection.DOWN)


def _key_up_event(keycode: int) -> HIDEvent:
    return HIDPress(action=HIDKey(keycode=keycode), direction=HIDDirection.UP)


def key_press_shifted_to_events(keycode: int) -> List[HIDEvent]:
    return [
        _key_down_event(225),
        _key_down_event(keycode),
        _key_up_event(keycode),
        _key_up_event(225),
    ]


KEY_MAP: Dict[str, List[HIDEvent]] = {
    "a": key_press_to_events(4),
    "b": key_press_to_events(5),
    "c": key_press_to_events(6),
    "d": key_press_to_events(7),
    "e": key_press_to_events(8),
    "f": key_press_to_events(9),
    "g": key_press_to_events(10),
    "h": key_press_to_events(11),
    "i": key_press_to_events(12),
    "j": key_press_to_events(13),
    "k": key_press_to_events(14),
    "l": key_press_to_events(15),
    "m": key_press_to_events(16),
    "n": key_press_to_events(17),
    "o": key_press_to_events(18),
    "p": key_press_to_events(19),
    "q": key_press_to_events(20),
    "r": key_press_to_events(21),
    "s": key_press_to_events(22),
    "t": key_press_to_events(23),
    "u": key_press_to_events(24),
    "v": key_press_to_events(25),
    "w": key_press_to_events(26),
    "x": key_press_to_events(27),
    "y": key_press_to_events(28),
    "z": key_press_to_events(29),
    "A": key_press_shifted_to_events(4),
    "B": key_press_shifted_to_events(5),
    "C": key_press_shifted_to_events(6),
    "D": key_press_shifted_to_events(7),
    "E": key_press_shifted_to_events(8),
    "F": key_press_shifted_to_events(9),
    "G": key_press_shifted_to_events(10),
    "H": key_press_shifted_to_events(11),
    "I": key_press_shifted_to_events(12),
    "J": key_press_shifted_to_events(13),
    "K": key_press_shifted_to_events(14),
    "L": key_press_shifted_to_events(15),
    "M": key_press_shifted_to_events(16),
    "N": key_press_shifted_to_events(17),
    "O": key_press_shifted_to_events(18),
    "P": key_press_shifted_to_events(19),
    "Q": key_press_shifted_to_events(20),
    "R": key_press_shifted_to_events(21),
    "S": key_press_shifted_to_events(22),
    "T": key_press_shifted_to_events(23),
    "U": key_press_shifted_to_events(24),
    "V": key_press_shifted_to_events(25),
    "W": key_press_shifted_to_events(26),
    "X": key_press_shifted_to_events(27),
    "Y": key_press_shifted_to_events(28),
    "Z": key_press_shifted_to_events(29),
    "1": key_press_to_events(30),
    "2": key_press_to_events(31),
    "3": key_press_to_events(32),
    "4": key_press_to_events(33),
    "5": key_press_to_events(34),
    "6": key_press_to_events(35),
    "7": key_press_to_events(36),
    "8": key_press_to_events(37),
    "9": key_press_to_events(38),
    "0": key_press_to_events(39),
    "\n": key_press_to_events(40),
    ";": key_press_to_events(51),
    "=": key_press_to_events(46),
    ",": key_press_to_events(54),
    "-": key_press_to_events(45),
    ".": key_press_to_events(55),
    "/": key_press_to_events(56),
    "`": key_press_to_events(53),
    "[": key_press_to_events(47),
    "\\": key_press_to_events(49),
    "]": key_press_to_events(48),
    "'": key_press_to_events(52),
    " ": key_press_to_events(44),
    "!": key_press_shifted_to_events(30),
    "@": key_press_shifted_to_events(31),
    "#": key_press_shifted_to_events(32),
    "$": key_press_shifted_to_events(33),
    "%": key_press_shifted_to_events(34),
    "^": key_press_shifted_to_events(35),
    "&": key_press_shifted_to_events(36),
    "*": key_press_shifted_to_events(37),
    "(": key_press_shifted_to_events(38),
    ")": key_press_shifted_to_events(39),
    "_": key_press_shifted_to_events(45),
    "+": key_press_shifted_to_events(46),
    "{": key_press_shifted_to_events(47),
    "}": key_press_shifted_to_events(48),
    ":": key_press_shifted_to_events(51),
    '"': key_press_shifted_to_events(52),
    "|": key_press_shifted_to_events(49),
    "<": key_press_shifted_to_events(54),
    ">": key_press_shifted_to_events(55),
    "?": key_press_shifted_to_events(56),
    "~": key_press_shifted_to_events(53),
}


def text_to_events(text: str) -> List[HIDEvent]:
    events = []
    for character in text:
        if character in KEY_MAP:
            events.extend(KEY_MAP[character])
        else:
            raise Exception(f"No keycode found for {character}")
    return events


async def iterator_to_async_iterator(
    events: Iterable[HIDEvent]
) -> AsyncIterator[HIDEvent]:
    for event in events:
        yield event
