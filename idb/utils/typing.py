#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import Optional, TypeVar


T = TypeVar("T")


def none_throws(optional: Optional[T]) -> T:
    assert optional is not None, "Unexpected None"
    return optional
