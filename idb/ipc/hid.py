#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import AsyncIterable, AsyncIterator, Dict, Iterable, List, Optional, Tuple

from idb.grpc.types import CompanionClient
from idb.grpc.stream import drain_to_stream
from idb.common.types import HIDButtonType
from idb.grpc.idb_pb2 import HIDEvent, Point


HIDButton = HIDEvent.HIDButton
HIDDelay = HIDEvent.HIDDelay
HIDKey = HIDEvent.HIDKey
HIDPress = HIDEvent.HIDPress
HIDPressAction = HIDEvent.HIDPressAction
HIDSwipe = HIDEvent.HIDSwipe
HIDTouch = HIDEvent.HIDTouch


def tap_to_events(x: int, y: int, duration: Optional[float] = None) -> List[HIDEvent]:
    return _press_with_duration(
        HIDPressAction(touch=HIDTouch(point=Point(x=x, y=y))), duration=duration
    )


def button_press_to_events(
    button: HIDButtonType, duration: Optional[float] = None
) -> List[HIDEvent]:
    # Need to convert between the py enum that starts at 1 and the grpc enum
    # that starts at 0
    return _press_with_duration(
        HIDPressAction(button=HIDButton(button=_translate_button_type(button))),
        duration=duration,
    )


def _translate_button_type(button: HIDButtonType) -> HIDEvent.HIDButtonType:
    if button == HIDButtonType.APPLE_PAY:
        return HIDEvent.APPLE_PAY
    elif button == HIDButtonType.HOME:
        return HIDEvent.HOME
    elif button == HIDButtonType.LOCK:
        return HIDEvent.LOCK
    elif button == HIDButtonType.SIDE_BUTTON:
        return HIDEvent.SIDE_BUTTON
    elif button == HIDButtonType.SIRI:
        return HIDEvent.SIRI
    raise Exception(f"Unexpected button type {button}")


def key_press_to_events(
    keycode: int, duration: Optional[float] = None
) -> List[HIDEvent]:
    return _press_with_duration(
        HIDPressAction(key=HIDKey(keycode=keycode)), duration=duration
    )


def _press_with_duration(
    action: HIDPressAction, duration: Optional[float] = None
) -> List[HIDEvent]:
    events = []
    events.append(HIDEvent(press=HIDPress(action=action, direction=HIDEvent.DOWN)))
    if duration:
        events.append(HIDEvent(delay=HIDDelay(duration=duration)))
    events.append(HIDEvent(press=HIDPress(action=action, direction=HIDEvent.UP)))
    return events


def swipe_to_events(
    p_start: Tuple[float, float],
    p_end: Tuple[float, float],
    delta: Optional[float] = None,
) -> List[HIDEvent]:
    start = Point(x=p_start[0], y=p_start[1])
    end = Point(x=p_end[0], y=p_end[1])
    return [HIDEvent(swipe=HIDSwipe(start=start, end=end, delta=delta))]


def _key_down_event(keycode: int) -> HIDEvent:
    return HIDEvent(
        press=HIDPress(
            action=HIDPressAction(key=HIDKey(keycode=keycode)), direction=HIDEvent.DOWN
        )
    )


def _key_up_event(keycode: int) -> HIDEvent:
    return HIDEvent(
        press=HIDPress(
            action=HIDPressAction(key=HIDKey(keycode=keycode)), direction=HIDEvent.UP
        )
    )


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


async def _iterator_to_async_iterator(
    events: Iterable[HIDEvent]
) -> AsyncIterator[HIDEvent]:
    for event in events:
        yield event


async def send_events(client: CompanionClient, events: Iterable[HIDEvent]) -> None:
    await hid(client, _iterator_to_async_iterator(events))


async def tap(
    client: CompanionClient, x: int, y: int, duration: Optional[float] = None
) -> None:
    await send_events(client, tap_to_events(x, y, duration))


async def button(
    client: CompanionClient,
    button_type: HIDButtonType,
    duration: Optional[float] = None,
) -> None:
    await send_events(client, button_press_to_events(button_type, duration))


async def key(
    client: CompanionClient, keycode: int, duration: Optional[float] = None
) -> None:
    await send_events(client, key_press_to_events(keycode, duration))


async def text(client: CompanionClient, text: str) -> None:
    await send_events(client, text_to_events(text))


async def swipe(
    client: CompanionClient,
    p_start: Tuple[int, int],
    p_end: Tuple[int, int],
    delta: Optional[int] = None,
) -> None:
    await send_events(client, swipe_to_events(p_start, p_end, delta))


async def key_sequence(client: CompanionClient, key_sequence: List[int]) -> None:
    events: List[HIDEvent] = []
    for key in key_sequence:
        events.extend(key_press_to_events(key))
    await send_events(client, events)


async def hid(client: CompanionClient, event_iterator: AsyncIterable[HIDEvent]) -> None:
    async with client.stub.hid.open() as stream:
        await drain_to_stream(
            stream=stream, generator=event_iterator, logger=client.logger
        )
        await stream.recv_message()


CLIENT_PROPERTIES = [tap, button, key, key_sequence, text, swipe, hid]  # pyre-ignore
