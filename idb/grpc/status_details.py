#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""The retry verdict the companion attaches to a failed UI automation call.

It travels in `grpc-status-details-bin` as a `google.rpc.Status` holding a
`google.rpc.ErrorInfo`. The client does not depend on googleapis, so the few
fields it needs are decoded here from the protobuf wire format.
"""

from collections.abc import Iterator
from typing import Any

from grpclib.const import Status
from grpclib.encoding.base import StatusDetailsCodecBase
from idb.common.types import RetryVerdict

_ERROR_INFO_TYPE_URL = b"type.googleapis.com/google.rpc.ErrorInfo"
_DOMAIN = "idb"
_REASON = "UI_AUTOMATION_FAILURE"


def _varint(data: bytes, offset: int) -> tuple[int, int]:
    result = shift = 0
    while True:
        if offset >= len(data):
            raise ValueError("truncated varint")
        byte = data[offset]
        offset += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, offset
        shift += 7


def _fields(data: bytes) -> Iterator[tuple[int, int | bytes]]:
    offset = 0
    while offset < len(data):
        key, offset = _varint(data, offset)
        number, wire_type = key >> 3, key & 7
        value: int | bytes
        if wire_type == 0:
            value, offset = _varint(data, offset)
        elif wire_type in (1, 2, 5):
            if wire_type == 2:
                length, offset = _varint(data, offset)
            else:
                length = 8 if wire_type == 1 else 4
            value = data[offset : offset + length]
            if len(value) != length:
                raise ValueError("truncated field")
            offset += length
        else:
            raise ValueError(f"unsupported wire type {wire_type}")
        yield number, value


def _strings(data: bytes) -> dict[int, str]:
    """Fields 1 and 2, which are the only strings in both an `ErrorInfo` and
    one of its metadata entries. Field 3 of an `ErrorInfo` holds the entries
    themselves, which are not text."""
    return {
        number: value.decode()
        for number, value in _fields(data)
        if number in (1, 2) and isinstance(value, bytes)
    }


def _error_info(data: bytes) -> tuple[str, str, dict[str, str]]:
    fields = _strings(data)
    metadata: dict[str, str] = {}
    for number, entry in _fields(data):
        if number == 3 and isinstance(entry, bytes):
            pair = _strings(entry)
            metadata[pair.get(1, "")] = pair.get(2, "")
    return fields.get(1, ""), fields.get(2, ""), metadata


def retry_verdict(data: bytes) -> RetryVerdict | None:
    """The verdict in a serialized `google.rpc.Status`, or None when it has
    none or cannot be read."""
    try:
        for number, detail in _fields(data):
            if number != 3 or not isinstance(detail, bytes):
                continue
            packed = dict(_fields(detail))
            info = packed.get(2)
            if packed.get(1) != _ERROR_INFO_TYPE_URL or not isinstance(info, bytes):
                continue
            reason, domain, metadata = _error_info(info)
            if reason != _REASON or domain != _DOMAIN:
                continue
            if "retry" not in metadata or "retry_reason" not in metadata:
                return None
            return RetryVerdict(
                verdict=metadata["retry"], reason=metadata["retry_reason"]
            )
    except ValueError:
        # Includes UnicodeDecodeError.
        return None
    return None


class RetryVerdictCodec(StatusDetailsCodecBase):
    """Decodes status details to a `RetryVerdict`, or None."""

    def encode(self, status: Status, message: str | None, details: Any) -> bytes:
        raise NotImplementedError("the idb client never sends status details")

    def decode(
        self, status: Status, message: str | None, data: bytes
    ) -> RetryVerdict | None:
        return retry_verdict(data)
