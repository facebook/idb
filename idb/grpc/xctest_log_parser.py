# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import json
from collections import defaultdict
from typing import Optional, Dict, List, NamedTuple


class XCTestLogParserKey(NamedTuple):
    className: str
    methodName: str


class Event(NamedTuple):
    event: str
    className: str
    methodName: str


XCTestLogParserData = Dict[XCTestLogParserKey, List[str]]


def _try_parse_event(log_line: str) -> Optional[Event]:
    event = None
    parsed_json = None
    if len(log_line) < 10_000:  # For performance reasons, don't parse long lines
        try:
            parsed_json = json.loads(log_line)
        except json.decoder.JSONDecodeError:
            pass

    keys = ["event", "className", "methodName"]
    if (
        isinstance(parsed_json, dict)
        and all(key in parsed_json for key in keys)
        and all(isinstance(parsed_json[key], str) for key in keys)
    ):
        event = Event(
            event=parsed_json["event"],
            className=parsed_json["className"],
            methodName=parsed_json["methodName"],
        )
    return event


class XCTestLogParser:
    _logs: XCTestLogParserData
    _current_test: Optional[XCTestLogParserKey]

    def __init__(self) -> None:
        self._logs = defaultdict(list)
        self._current_test = None

    def parse_streaming_log(self, line: str) -> None:
        event = _try_parse_event(line)
        if event is None:
            self._append_line_to_test(line)
        elif event.event == "begin-test":
            self._current_test = XCTestLogParserKey(
                className=event.className,
                methodName=event.methodName,
            )
        elif event.event == "end-test":
            self._current_test = None

    def get_logs_for_test(self, class_name: str, method_name: str) -> List[str]:
        key = XCTestLogParserKey(className=class_name, methodName=method_name)
        return self._logs[key]

    def _append_line_to_test(self, line: str) -> None:
        key = self._current_test
        if key is not None:
            self._logs[key].append(line)
