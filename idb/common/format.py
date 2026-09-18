#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import base64
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from textwrap import indent
from typing import Any, Dict, List, Optional, Union

from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    DebuggerInfo,
    DeliveredNotification,
    DomainSocketAddress,
    IdbException,
    InstalledAppInfo,
    InstalledTestInfo,
    TargetDescription,
    TargetType,
    TCPAddress,
    TestActivity,
    TestRunInfo,
)


def target_type_from_string(output: str) -> TargetType:
    normalized = output.lower()
    if "sim" in normalized:
        return TargetType.SIMULATOR
    if "dev" in normalized:
        return TargetType.DEVICE
    if "mac" in normalized:
        return TargetType.MAC
    raise IdbException(f"Could not interpret target type from {output}")


def test_info_to_status(test: TestRunInfo) -> str:
    if test.passed:
        return "passed"
    if test.crashed:
        return "crashed"
    return "failed"


def human_format_test_info(test: TestRunInfo) -> str:
    output = ""

    info_list = [
        f"{test.bundle_name} - {test.class_name}/{test.method_name}",
        f"Status: {test_info_to_status(test)}",
        f"Duration: {test.duration}",
    ]
    failure_info = test.failure_info
    if failure_info is not None and len(failure_info.message):
        info_list += [
            f"Failure message: {failure_info.message}",
            f"Location {failure_info.file}:{failure_info.line}",
        ]
    output += " | ".join(info_list)

    if len(test.logs) > 0:
        log_lines = indent("\n".join(test.logs), " " * 4)
        output += "\n" + indent("Logs:\n" + log_lines, " " * 4)

    activities = test.activityLogs
    if activities is not None and len(activities):
        output += f"\n{human_format_activities(activities)}"
    return output


@dataclass(frozen=True)
class _ActivityNode:
    start: float
    label: str
    children: list["_ActivityNode"]


def _activity_node(activity: TestActivity, base: float) -> _ActivityNode:
    children = [
        # An attachment has no start of its own; it inherits its parent
        # activity's so it orders among that activity's sub-activities.
        _ActivityNode(
            start=activity.start,
            label=f"Attachment: {attachment.name}",
            children=[],
        )
        for attachment in activity.attachments
    ]
    children.extend(
        _activity_node(sub_activity, base) for sub_activity in activity.sub_activities
    )
    return _ActivityNode(
        start=activity.start,
        label=f"{activity.name} ({activity.finish - base:.2f}s)",
        children=children,
    )


def _render_children(nodes: list[_ActivityNode], prefix: str) -> list[str]:
    lines: list[str] = []
    ordered = sorted(nodes, key=lambda node: node.start)
    for index, node in enumerate(ordered):
        last = index == len(ordered) - 1
        lines.append(f"{prefix}{'└── ' if last else '├── '}{node.label}")
        lines.extend(
            _render_children(node.children, prefix + ("    " if last else "│   "))
        )
    return lines


def human_format_activities(activities: list[TestActivity]) -> str:
    base: float = activities[0].start
    nodes = [_activity_node(activity, base) for activity in activities]
    return "\n".join(["Activities", *_render_children(nodes, "")]) + "\n"


def json_format_test_info(test: TestRunInfo) -> str:
    data: dict[str, Any] = {
        "bundleName": test.bundle_name,
        "className": test.class_name,
        "methodName": test.method_name,
        "logs": test.logs,
        "duration": test.duration,
        "passed": test.passed,
        "crashed": test.crashed,
        "status": test_info_to_status(test),
    }
    failure_info = test.failure_info
    if failure_info is not None and len(failure_info.message):
        data["failureInfo"] = {
            "message": failure_info.message,
            "file": failure_info.file,
            "line": failure_info.line,
        }
    activities = test.activityLogs
    if activities is not None and len(activities):
        data["activityLogs"] = [
            json_format_activity(activity) for activity in activities
        ]
    return json.dumps(data)


def json_format_activity(activity: TestActivity) -> dict[str, Any]:
    return {
        "title": activity.title,
        "duration": activity.duration,
        "uuid": activity.uuid,
        "activity_type": activity.activity_type,
        "start": activity.start,
        "finish": activity.finish,
        "name": activity.name,
        "attachments": [
            {
                "payload": base64.b64encode(attachment.payload).decode("utf-8"),
                "timestap": attachment.timestamp,
                "name": attachment.name,
                "uniform_type_identifier": attachment.uniform_type_identifier,
                "user_info": (
                    json.loads(attachment.user_info_json.decode("utf-8"))
                    if len(attachment.user_info_json)
                    else {}
                ),
            }
            for attachment in activity.attachments
        ],
        "sub_activities": [
            json_format_activity(sub_activity)
            for sub_activity in activity.sub_activities
        ],
    }


def human_format_installed_app_info(app: InstalledAppInfo) -> str:
    return " | ".join(
        [
            app.bundle_id,
            app.name or "no bundle name available",
            app.install_type or "no install type available",
            ", ".join(app.architectures or ["no archs available"]),
            app_process_state_to_string(app.process_state),
            "Debuggable" if app.debuggable else "Not Debuggable",
            f"pid={app_process_id_based_on_state(app.process_id, app.process_state)}",
        ]
    )


def app_process_id_based_on_state(
    pid: int,
    state: AppProcessState,
) -> str | None:
    if state is AppProcessState.RUNNING:
        return str(pid)
    return None


def app_process_state_to_string(state: AppProcessState | None) -> str:
    if state is AppProcessState.RUNNING:
        return "Running"
    elif state is AppProcessState.NOT_RUNNING:
        return "Not running"
    else:
        return "Unknown"


def app_process_string_to_state(output: str) -> AppProcessState:
    if output == "Running":
        return AppProcessState.RUNNING
    elif output == "Not running":
        return AppProcessState.NOT_RUNNING
    else:
        return AppProcessState.UNKNOWN


def json_format_installed_app_info(app: InstalledAppInfo) -> str:
    data = {
        "bundle_id": app.bundle_id,
        "name": app.name,
        "install_type": app.install_type,
        "architectures": list(app.architectures) if app.architectures else None,
        "process_state": app_process_state_to_string(app.process_state),
        "debuggable": app.debuggable,
        "pid": app_process_id_based_on_state(app.process_id, app.process_state),
    }
    return json.dumps(data)


def human_format_target_info(target: TargetDescription) -> str:
    target_info = (
        f"{target.name} | {target.udid} | {target.state}"
        f" | {target.target_type.value} | {target.os_version} | {target.architecture} | "
    )
    companion_info = target.companion_info
    if companion_info is None:
        return target_info + "No Companion Connected"
    address = companion_info.address
    if isinstance(address, TCPAddress):
        return target_info + f"{address.host}:{address.port}"
    else:
        return target_info + f"{address.path}"


def json_data_target_info(target: TargetDescription) -> dict[str, Any]:
    data: dict[str, Any] = {
        "name": target.name,
        "udid": target.udid,
        "state": target.state,
        "type": target.target_type.value,
        "os_version": target.os_version,
        "architecture": target.architecture,
    }
    companion_info = target.companion_info
    if companion_info is not None:
        address = companion_info.address
        if isinstance(address, TCPAddress):
            data["host"] = address.host
            data["port"] = address.port
            data["is_local"] = companion_info.is_local
            data["companion"] = f"{address.host}:{address.port}"
        else:
            data["path"] = address.path
            data["is_local"] = True
            data["companion"] = address.path
    if target.device is not None:
        data["device"] = target.device
    return data


def json_data_companions(
    companions: list[CompanionInfo],
) -> list[dict[str, str | int | None]]:
    data: list[dict[str, str | int | None]] = []
    for companion in companions:
        item: dict[str, str | int | None] = {
            "udid": companion.udid,
            "is_local": companion.is_local,
            "pid": companion.pid,
        }
        address = companion.address
        if isinstance(address, TCPAddress):
            item["host"] = address.host
            item["port"] = address.port
        else:
            item["path"] = address.path
        data.append(item)
    return data


def json_to_companion_info(data: list[dict[str, Any]]) -> list[CompanionInfo]:
    return [
        CompanionInfo(
            udid=item["udid"],
            address=(
                TCPAddress(host=item["host"], port=item["port"])
                if "host" in item
                else DomainSocketAddress(path=item["path"])
            ),
            is_local=item["is_local"],
            pid=item.get("pid"),
        )
        for item in data
    ]


def target_description_from_json(data: str) -> TargetDescription:
    return target_description_from_dictionary(parsed=json.loads(data))


def target_descriptions_from_json(data: str) -> list[TargetDescription]:
    return [
        target_description_from_dictionary(parsed=target) for target in json.loads(data)
    ]


def target_description_from_dictionary(parsed: dict[str, Any]) -> TargetDescription:
    return TargetDescription(
        udid=parsed["udid"],
        name=parsed["name"],
        model=parsed.get("model"),
        state=parsed.get("state"),
        target_type=target_type_from_string(parsed["type"]),
        os_version=parsed.get("os_version"),
        architecture=parsed.get("architecture"),
        companion_info=None,
        screen_dimensions=None,
        device=parsed.get("device"),
    )


def json_format_target_info(target: TargetDescription) -> str:
    return json.dumps(json_data_target_info(target=target))


def human_format_installed_test_info(test: InstalledTestInfo) -> str:
    return " | ".join(
        [
            test.bundle_id,
            test.name or "no bundle name available",
            ", ".join(test.architectures or ["no archs available"]),
        ]
    )


def json_format_installed_test_info(test: InstalledTestInfo) -> str:
    data = {
        "bundle_id": test.bundle_id,
        "name": test.name,
        "architectures": list(test.architectures) if test.architectures else None,
    }
    return json.dumps(data)


def json_format_debugger_info(info: DebuggerInfo) -> str:
    data = {
        "pid": info.pid,
    }
    return json.dumps(data)


def _quoted(text: str) -> str:
    """Quotes and escapes the way JSON writes a string, so that a newline in
    text the sending app chose cannot end the record early. A ` | ` inside the
    quotes is still a ` | `, so the quotes show where a field ends rather than
    making a naive split safe; `--json` is the form to parse.

    Only what would break the line is escaped: a title in an alphabet other than
    this one, or with an emoji in it, stays as the app wrote it rather than being
    written out as `\\uXXXX` escapes for a person to decode. An empty field is
    written as `""`, since every string here is one the app set or left empty --
    there is no absent case to keep it distinct from.
    """
    return (
        json.dumps(text, ensure_ascii=False)
        .replace("\u0085", "\\u0085")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )


def _human_date(date: Optional[float]) -> str:
    """Renders a wire date, or says it could not be.

    The wire field is a double the companion read off the device, so it can be one
    no platform can turn into a date -- outside `time_t`, or a NaN. Listing the other
    notifications is worth more than raising on one bad field, and `--json` still
    carries a finite one as it arrived for anyone who wants to look.
    """
    if date is None:
        return "no date"
    try:
        return datetime.fromtimestamp(date, timezone.utc).isoformat()
    except (OverflowError, OSError, ValueError):
        return "unreadable date"


def human_format_delivered_notification(notification: DeliveredNotification) -> str:
    return " | ".join(
        [
            _quoted(notification.bundle_id),
            _quoted(notification.identifier),
            _quoted(notification.title),
            _quoted(notification.subtitle),
            _quoted(notification.body),
            _quoted(notification.thread_identifier),
            _human_date(notification.date),
        ]
    )


def _json_date(date: Optional[float]) -> Optional[float]:
    """The wire date as JSON can carry it, or `None` where it cannot.

    JSON has no number for an infinity or a NaN, and `json.dumps` writes one as a
    bare `Infinity` or `NaN` that a strict reader rejects -- so a single bad field
    would cost the caller the whole record rather than just that field. `null` is
    what an absent date already reads as, and it is the one value every reader
    already has for "no date here". The human format still tells the two apart.
    """
    if date is None or not math.isfinite(date):
        return None
    return date


def json_format_delivered_notification(notification: DeliveredNotification) -> str:
    data = {
        "bundle_id": notification.bundle_id,
        "identifier": notification.identifier,
        "title": notification.title,
        "subtitle": notification.subtitle,
        "body": notification.body,
        "thread_identifier": notification.thread_identifier,
        "date": _json_date(notification.date),
    }
    # Nothing above can reach this with a non-finite value any more; `allow_nan=False`
    # is so that anything that later does raises here rather than printing a line no
    # strict reader will take.
    return json.dumps(data, allow_nan=False)
