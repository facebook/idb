#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
from typing import Dict


def get_env_with_idb_prefix() -> Dict[str, str]:
    env = dict(os.environ)
    env = {key: env[key] for key in env if key.startswith("IDB_")}
    return {key[len("IDB_") :]: env[key] for key in env}
