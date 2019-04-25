#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from idb.common.types import TargetDescription


def mock_target(
    udid: str = "udid",
    name: str = "name",
    screen_dimensions: None = None,
    state: str = "state",
    target_type: str = "type",
    os_version: str = "os_version",
    architecture: str = "arch",
    companion_info: None = None,
) -> TargetDescription:
    return TargetDescription(
        udid=udid,
        name=name,
        screen_dimensions=screen_dimensions,
        state=state,
        target_type=target_type,
        os_version=os_version,
        architecture=architecture,
        companion_info=companion_info,
    )
