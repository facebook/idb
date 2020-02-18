#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


from logging import Logger
from typing import List, NamedTuple, Optional, Sequence

from idb.common.types import TargetDescription
from idb.grpc.idb_grpc import CompanionServiceStub


class CompanionClient(NamedTuple):
    stub: CompanionServiceStub
    is_local: bool
    udid: Optional[str]
    logger: Logger
    is_companion_available: bool = False


def merge_connected_targets(
    local_targets: Sequence[TargetDescription],
    connected_targets: Sequence[TargetDescription],
) -> List[TargetDescription]:
    connected_mapping = {target.udid: target for target in connected_targets}
    targets = {}
    # First, add all local targets, updating companion info where available
    for target in local_targets:
        udid = target.udid
        if udid in connected_mapping:
            targets[udid] = connected_mapping[udid]
        else:
            targets[udid] = target
    # Then add the connected targets that aren't local
    for target in connected_targets:
        udid = target.udid
        if udid in targets:
            continue
        targets[udid] = target
    return list(targets.values())
