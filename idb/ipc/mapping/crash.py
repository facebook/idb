#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import List

from idb.common.types import CrashLog, CrashLogInfo, CrashLogQuery
from idb.grpc.idb_pb2 import (
    CrashLogInfo as CrashLogInfoProto,
    CrashLogQuery as CrashLogQueryProto,
    CrashLogResponse,
    CrashShowResponse,
)


def _to_crash_log_info_list(response: CrashLogResponse) -> List[CrashLogInfo]:
    return [_to_crash_log_info(proto) for proto in response.list]


def _to_crash_log_info(proto: CrashLogInfoProto) -> CrashLogInfo:
    return CrashLogInfo(
        name=proto.name,
        bundle_id=proto.bundle_id,
        process_name=proto.process_name,
        parent_process_name=proto.parent_process_name,
        process_identifier=proto.process_identifier,
        parent_process_identifier=proto.parent_process_identifier,
        timestamp=proto.timestamp,
    )


def _to_crash_log(proto: CrashShowResponse) -> CrashLog:
    return CrashLog(info=_to_crash_log_info(proto.info), contents=proto.contents)


def _to_crash_log_query_proto(query: CrashLogQuery) -> CrashLogQueryProto:
    return CrashLogQueryProto(
        before=query.before,
        since=query.since,
        bundle_id=query.bundle_id,
        name=query.name,
    )
