#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# pyre-strict


def get_last_n_lines(file_path: str, n: int) -> str:
    with open(file_path, "r") as f:
        return "\n".join(f.readlines()[-n:])
