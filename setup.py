#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import os
import sys
from pathlib import Path
from posix import chmod

import setuptools
import setuptools.command.build_py


def gen_protoc_complier():
    cur_dir = os.path.dirname(__file__)
    template_name = "protoc_compiler_template.py"
    with open(os.path.join(cur_dir, template_name)) as fd:
        template_py = fd.read()

    target_name = os.path.join(cur_dir, "protoc-gen-python_grpc")
    with open(target_name, "w") as fd:
        content = "#!%s\n" % sys.executable + template_py
        fd.write(content)
    chmod(target_name, 0o755)
    os.environ["PATH"] = cur_dir + os.pathsep + os.environ["PATH"]


class BuildPyCommand(setuptools.command.build_py.build_py):
    def run(self) -> None:
        super().run()

        # Generate pure python protoc compiler
        gen_protoc_complier()

        # Paths
        root = Path(os.path.realpath(__file__)).parent
        proto_file = root / "proto" / "idb.proto"
        output_dir = root / "build" / "lib" / "idb" / "grpc"
        grpclib_output = output_dir / "idb_grpc.py"

        # Generate the grpc files
        output_dir.mkdir(parents=True, exist_ok=True)
        command = [
            "grpc_tools.protoc",
            "--proto_path={}".format(proto_file.parent),
            "--python_out={}".format(output_dir),
            "--python_grpc_out={}".format(output_dir),
        ] + [str(proto_file)]
        # Needs to be imported after setuptools has ensured grpcio-tools is
        # installed
        from grpc_tools import protoc  # pyre-ignore

        if protoc.main(command) != 0:
            raise Exception("error: {} failed".format(command))

        # Fix the import paths
        with open(grpclib_output, "r") as file:
            filedata = file.read()
        filedata = filedata.replace(
            "import idb_pb2", "import idb.grpc.idb_pb2 as idb_pb2"
        )
        with open(grpclib_output, "w") as file:
            file.write(filedata)


version = os.environ.get("FB_IDB_VERSION")
if not version:
    raise Exception(
        """Cannot build with without a version number. Set the environment variable FB_IDB_VERSION"""
    )

setuptools.setup(
    name="fb-idb",
    version=version,
    author="Facebook",
    author_email="callumryan@fb.com",
    description="iOS debug bridge",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    url="https://github.com/facebook/idb",
    packages=setuptools.find_packages(),
    data_files=[("proto", ["proto/idb.proto"]), ("", ["protoc_compiler_template.py"])],
    license="MIT",
    classifiers=[
        "Programming Language :: Python :: 3.6",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    install_requires=["aiofiles", "grpclib >= 0.4.0", "protobuf", "treelib"],
    setup_requires=["grpcio-tools >= 1.29.0", "grpclib >= 0.3.2"],
    entry_points={"console_scripts": ["idb = idb.cli.main:main"]},
    python_requires=">=3.7",
    cmdclass={"build_py": BuildPyCommand},
)
