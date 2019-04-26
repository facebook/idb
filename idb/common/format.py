#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import json
from textwrap import indent
from typing import Any, Dict, Optional

from idb.common.types import (
    AppProcessState,
    InstalledAppInfo,
    InstalledTestInfo,
    TargetDescription,
    TestActivity,
    TestRunInfo,
)


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

    return output


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
            json_format_activity(activity)
            for activity in test.activityLogs  # pyre-fixme: Optional iter
        ],
    }
    return json.dumps(data)


def json_format_activity(activity: TestActivity) -> Dict[str, Any]:
    return {
        "title": activity.title,
        "duration": activity.duration,
        "uuid": activity.uuid,
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
    return data


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
