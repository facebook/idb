#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

from typing import Optional, TypeVar


T = TypeVar("T")


def none_throws(optional: Optional[T]) -> T:
    assert optional is not None, "Unexpected None"
    return optional
