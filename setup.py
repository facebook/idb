#!/usr/bin/env python3

import os
import setuptools
import setuptools.command.build_py

from pathlib import Path


class BuildPyCommand(setuptools.command.build_py.build_py):
    def run(self) -> None:
        super().run()
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
        # Needs to be imported after setuptools has ensured grpcio-tools is installed
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


setuptools.setup(
    name="fb-idb",
    version="0.0.1",
    author="Facebook",
    author_email="callumryan@fb.com",
    description="iOS debug bridge",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    url="https://github.com/facebook/idb",
    packages=setuptools.find_packages(),
    license="MIT",
    classifiers=[
        "Programming Language :: Python :: 3.6",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
    ],
    install_requires=["aiofiles", "grpclib", "protobuf"],
    setup_requires=["grpcio-tools", "grpclib"],
    entry_points={"console_scripts": ["idb = idb.cli.main:main"]},
    python_requires=">=3.6",
    cmdclass={"build_py": BuildPyCommand},
)
