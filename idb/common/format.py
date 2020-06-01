#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import base64
import json
from textwrap import indent
from typing import Any, Dict, List, Optional
from uuid import uuid4

from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    InstalledAppInfo,
    InstalledTestInfo,
    TargetDescription,
    TestActivity,
    TestRunInfo,
)
from treelib import Tree


def human_format_test_info(test: TestRunInfo) -> str:
    output = ""

    info_list = [
        f"{test.bundle_name} - {test.class_name}/{test.method_name}",
        f"Passed: {test.passed}",
        f"Crashed: {test.crashed}",
        f"Duration: {test.duration}",
    ]
    failure_info = test.failure_info
    if failure_info:
        info_list += [
            f"Failure message: {failure_info.message}",
            f"Location {failure_info.file}:{failure_info.line}",
        ]
    output += " | ".join(info_list)

    if len(test.logs) > 0:
        log_lines = indent("\n".join(test.logs), " " * 4)
        output += "\n" + indent("Logs:\n" + log_lines, " " * 4)

    if test.activityLogs:
        output += f"\n{human_format_activities(test.activityLogs)}"
    return output


def human_format_activities(activities: List[TestActivity]) -> str:
    tree: Tree = Tree()
    start = activities[0].start

    def process_activity(activity: TestActivity, parent: Optional[str] = None) -> None:
        tree.create_node(
            f"{activity.name} ({activity.finish - start:.2f}s)",
            activity.uuid,
            parent=parent,
        )
        for attachment in activity.attachments:
            tree.create_node(
                f"Attachment: {attachment.name}", uuid4(), parent=activity.uuid
            )
        for sub_activity in activity.sub_activities:
            process_activity(sub_activity, parent=activity.uuid)

    tree.create_node("Activities", "activities")
    for activity in activities:
        process_activity(activity, "activities")

    return str(tree)


def json_format_test_info(test: TestRunInfo) -> str:
    failure_info = test.failure_info
    data = {
        "bundleName": test.bundle_name,
        "className": test.class_name,
        "methodName": test.method_name,
        "logs": test.logs,
        "duration": test.duration,
        "passed": test.passed,
        "crashed": test.crashed,
        "failureInfo": {
            "message": failure_info.message,
            "file": failure_info.file,
            "line": failure_info.line,
        }
        if failure_info
        else None,
        "activityLogs": [
            json_format_activity(activity) for activity in (test.activityLogs or [])
        ],
    }
    return json.dumps(data)


def json_format_activity(activity: TestActivity) -> Dict[str, Any]:
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
        ]
    )


def app_process_state_to_string(state: Optional[AppProcessState]) -> str:
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
    }
    return json.dumps(data)


def human_format_target_info(target: TargetDescription) -> str:
    target_info = (
        f"{target.name} | {target.udid} | {target.state}"
        f" | {target.target_type} | {target.os_version} | {target.architecture}"
    )
    target_info += (
        f" | {target.companion_info.host}:{target.companion_info.port}"
        if target.companion_info
        else f" | No Companion Connected"
    )
    return target_info


def json_data_target_info(target: TargetDescription) -> Dict[str, Any]:
    data: Dict[str, Any] = {
        "name": target.name,
        "udid": target.udid,
        "state": target.state,
        "type": target.target_type,
        "os_version": target.os_version,
        "architecture": target.architecture,
    }
    if target.companion_info:
        data["host"] = target.companion_info.host
        data["port"] = target.companion_info.port
        data["is_local"] = target.companion_info.is_local
    if target.device is not None:
        data["device"] = target.device
    return data


def json_data_companions(companions: List[CompanionInfo]) -> List[Dict[str, Any]]:
    data: List[Dict[str, Any]] = []
    for companion in companions:
        data.append(
            {
                "host": companion.host,
                "udid": companion.udid,
                "port": companion.port,
                "is_local": companion.is_local,
            }
        )
    return data


def json_to_companion_info(data: List[Dict[str, Any]]) -> List[CompanionInfo]:
    companion_list = []
    for item in data:
        companion_list.append(
            CompanionInfo(
                udid=item["udid"],
                host=item["host"],
                port=item["port"],
                is_local=item["is_local"],
            )
        )
    return companion_list


def target_description_from_json(data: str) -> TargetDescription:
    return target_description_from_dictionary(parsed=json.loads(data))


def target_description_from_dictionary(parsed: Dict[str, Any]) -> TargetDescription:
    return TargetDescription(
        udid=parsed["udid"],
        name=parsed["name"],
        model=parsed.get("model"),
        state=parsed.get("state"),
        target_type=parsed.get("type"),
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
