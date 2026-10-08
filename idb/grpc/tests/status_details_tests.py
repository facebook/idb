#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.


import unittest

from grpclib.const import Status
from grpclib.exceptions import GRPCError
from idb.common.types import IdbException, RetryVerdict
from idb.grpc.client import log_and_handle_exceptions
from idb.grpc.status_details import retry_verdict, RetryVerdictCodec
from idb.utils.testing import TestCase


def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def _field(number: int, value: bytes | str) -> bytes:
    data = value.encode() if isinstance(value, str) else value
    return _varint(number << 3 | 2) + _varint(len(data)) + data


def _status(
    metadata: dict[str, str],
    reason: str = "UI_AUTOMATION_FAILURE",
    domain: str = "idb",
    type_url: str = "type.googleapis.com/google.rpc.ErrorInfo",
) -> bytes:
    info = _field(1, reason) + _field(2, domain)
    for key, value in metadata.items():
        info += _field(3, _field(1, key) + _field(2, value))
    packed = _field(1, type_url) + _field(2, info)
    return _varint(1 << 3) + _varint(13) + _field(2, "the message") + _field(3, packed)


VERDICT = {"retry": "safe_after_reread", "retry_reason": "nothing_written"}


class RetryVerdictTests(unittest.TestCase):
    def test_reads_the_verdict_from_the_error_info(self) -> None:
        expected = RetryVerdict(verdict="safe_after_reread", reason="nothing_written")
        self.assertEqual(retry_verdict(_status(VERDICT)), expected)
        # A metadata entry of 128 bytes or more has a length prefix that is not
        # valid UTF-8, so it must not be decoded as part of the ErrorInfo.
        self.assertEqual(
            retry_verdict(_status({**VERDICT, "detail": "x" * 128})), expected
        )

    def test_an_error_info_from_elsewhere_has_no_verdict(self) -> None:
        self.assertIsNone(retry_verdict(_status(VERDICT, domain="example.com")))
        self.assertIsNone(retry_verdict(_status(VERDICT, reason="QUOTA")))
        self.assertIsNone(
            retry_verdict(
                _status(VERDICT, type_url="type.googleapis.com/google.rpc.RetryInfo")
            )
        )

    def test_an_error_info_missing_either_key_has_no_verdict(self) -> None:
        self.assertIsNone(retry_verdict(_status({"retry": "safe"})))
        self.assertIsNone(retry_verdict(_status({"retry_reason": "idempotent"})))

    def test_unreadable_details_have_no_verdict(self) -> None:
        self.assertIsNone(retry_verdict(_status(VERDICT)[:-3]))
        self.assertIsNone(retry_verdict(b"\xff"))
        self.assertIsNone(retry_verdict(b""))

    def test_the_codec_decodes_to_the_verdict(self) -> None:
        self.assertEqual(
            RetryVerdictCodec().decode(Status.INTERNAL, "m", _status(VERDICT)),
            RetryVerdict(verdict="safe_after_reread", reason="nothing_written"),
        )


async def _raise_through_the_client(error: GRPCError) -> None:
    @log_and_handle_exceptions("tap")
    async def call() -> None:
        raise error

    await call()


class IdbExceptionTests(TestCase):
    async def _raised(self, error: GRPCError) -> IdbException:
        with self.assertRaises(IdbException) as context:
            await _raise_through_the_client(error)
        return context.exception

    async def test_a_decoded_verdict_is_kept_beside_the_unchanged_message(
        self,
    ) -> None:
        verdict = RetryVerdict(verdict="unsafe", reason="outcome_unknown")
        error = await self._raised(
            GRPCError(Status.INTERNAL, "did not answer", verdict)
        )
        self.assertEqual(error.args, ("did not answer",))
        self.assertEqual(error.retry, verdict)

    async def test_no_details_means_no_verdict(self) -> None:
        error = await self._raised(GRPCError(Status.INTERNAL, "did not answer"))
        self.assertEqual(error.args, ("did not answer",))
        self.assertIsNone(error.retry)

    def test_a_raised_exception_has_no_verdict_by_default(self) -> None:
        self.assertIsNone(IdbException("boom").retry)
