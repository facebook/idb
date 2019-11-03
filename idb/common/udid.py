#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import re


SIMULATOR_UDID = r"^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$"
OLD_DEVICE_UDID = r"^[0-9a-f]{40}$"
NEW_DEVICE_UDID = r"^[0-9]{8}-[0-9A-F]{16}$"
UDID = fr"({SIMULATOR_UDID}|{OLD_DEVICE_UDID}|{NEW_DEVICE_UDID})"


def is_udid(udid: str) -> bool:
    return bool(re.match(UDID, udid))
