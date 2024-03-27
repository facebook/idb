#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict

import base64
import json
from textwrap import indent
from typing import Any, Dict, List, Optional, Union
from uuid import uuid4

from idb.common.types import (
    AppProcessState,
    CompanionInfo,
    DebuggerInfo,
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
from treelib import Tree


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


def human_format_activities(activities: List[TestActivity]) -> str:
    tree: Tree = Tree()
    start: float = activities[0].start

    def process_activity(activity: TestActivity, parent: Optional[str] = None) -> None:
        tree.create_node(
            f"{activity.name} ({activity.finish - start:.2f}s)",
            activity.uuid,
            parent=parent,
            data={"start": activity.start},
        )
        for attachment in activity.attachments:
            tree.create_node(
                f"Attachment: {attachment.name}",
                uuid4(),
                parent=activity.uuid,
                data={"start": activity.start},
            )
        for sub_activity in activity.sub_activities:
            process_activity(sub_activity, parent=activity.uuid)

    tree.create_node("Activities", "activities", data={"start": 0})
    for activity in activities:
        process_activity(activity, "activities")

    return tree.show(key=lambda n: n.data["start"], stdout=False)


def json_format_test_info(test: TestRunInfo) -> str:
    data: Dict[str, Any] = {
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
) -> Optional[str]:
    if state is AppProcessState.RUNNING:
        return str(pid)
    return None


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


def json_data_target_info(target: TargetDescription) -> Dict[str, Any]:
    data: Dict[str, Any] = {
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
    companions: List[CompanionInfo],
) -> List[Dict[str, Union[str, Optional[int]]]]:
    data: List[Dict[str, Union[str, Optional[int]]]] = []
    for companion in companions:
        item: Dict[str, Union[str, Optional[int]]] = {
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


def json_to_companion_info(data: List[Dict[str, Any]]) -> List[CompanionInfo]:
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


def target_descriptions_from_json(data: str) -> List[TargetDescription]:
    return [
        target_description_from_dictionary(parsed=target) for target in json.loads(data)
    ]


def target_description_from_dictionary(parsed: Dict[str, Any]) -> TargetDescription:
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
