# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Protoc plugin shim for grpclib's python_grpc generator. setup.py writes this
# file out as an executable named `protoc-gen-python_grpc`, prefixed with the
# build interpreter's shebang, so `grpc_tools.protoc` can spawn it from PATH.
import sys

from grpclib.plugin.main import main

if __name__ == "__main__":
    sys.exit(main())
