#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import argparse
import os
from typing import List, Optional


class KeyValueDictAppendAction(argparse.Action):
    """
    argparse action to split an argument into KEY=VALUE form
    on the first = and append to a dictionary.
    """

    def __call__(
        self,
        parser: argparse.ArgumentParser,
        namespace: argparse.Namespace,
        values: List[str],
        option_string: Optional[str] = None,
    ) -> None:
        assert len(values) == 1
        try:
            (k, v) = values[0].split("=", 2)
        except ValueError as ex:
            raise argparse.ArgumentError(
                self, f'could not parse argument "{values[0]}" as k=v format'
            ) from ex
        d = getattr(namespace, self.dest) or {}
        d[k] = v
        setattr(namespace, self.dest, d)


def have_file_with_extension(file_prefix: str, extensions: List[str]) -> bool:
    return any(
        (os.path.exists(f"{file_prefix}.{extension}") for extension in extensions)
    )


def find_next_file_prefix(basename: str, extensions: Optional[List[str]] = None) -> str:
    extensions = extensions or []
    number = 1
    while True:
        file_prefix = f"{basename}_{number:03d}"
        if have_file_with_extension(file_prefix, extensions):
            number += 1
        else:
            return file_prefix
