#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

import hashlib
import os
import subprocess
import tempfile


class bcolors:
    HEADER = "\033[95m"
    OKGREEN = "\033[92m"
    ENDC = "\033[0m"


release = os.getenv("NEW")
if not release:
    raise Exception("set release via `export NEW=<release>`")

dirpath = tempfile.mkdtemp()


print(
    bcolors.HEADER
    + "Preparing new OSS build. This script assumes that you already created new release on github. To create a release do:"
    + bcolors.ENDC
)
print('    gh release create v$NEW -t "<RELEASE_DATE>" -d --repo facebook/idb\n')

print(bcolors.OKGREEN + "Step 1. " + bcolors.ENDC + "Building to", dirpath)
subprocess.run(["./idb_build.sh", "idb_companion", "build", dirpath], check=True)

print(bcolors.OKGREEN + "Step 2. " + bcolors.ENDC + "Compressing the build")

subprocess.run(
    ["tar", "-cjf", "idb-companion.universal.tar.gz", "-C", dirpath, "."], check=True
)


print(bcolors.OKGREEN + "Step 3. " + bcolors.ENDC + "Calculating shasum")
with open("idb-companion.universal.tar.gz", "rb") as f:
    bytes = f.read()  # read entire file as bytes
    readable_hash = hashlib.sha256(bytes).hexdigest()

print(readable_hash)

print(
    bcolors.OKGREEN + "Step 4. " + bcolors.ENDC + "Uploading the binary to gh release"
)
subprocess.run(
    [
        "gh",
        "release",
        "upload",
        "v" + release,
        "idb-companion.universal.tar.gz",
        "--repo",
        "facebook/idb",
    ]
)

binary_url = f"https://github.com/facebook/idb/releases/download/v{release}/idb-companion.universal.tar.gz"
print("New binary uploaded. It should be available by", binary_url)

subprocess.run(["brew", "tap", "facebook/fb"])

proc = subprocess.Popen(["brew", "--repo", "facebook/fb"], stdout=subprocess.PIPE)

homebrew_fb_repo_path = proc.stdout.read()[:-1].decode()

idb_companion_homebrew_config = homebrew_fb_repo_path + "/idb-companion.rb"
print(
    bcolors.OKGREEN + "Step 5. " + bcolors.ENDC + "Modifying",
    idb_companion_homebrew_config,
)

subprocess.run(
    [
        "sed",
        "-i",
        "",
        's/url ".*"/url "https://github.com/facebook/idb/releases/download/v{}/idb-companion.universal.tar.gz"/g'.format(
            release
        ),
        "idb-companion.rb",
    ],
    cwd=homebrew_fb_repo_path,
    check=True,
)
subprocess.run(
    [
        "sed",
        "-i",
        "",
        f's/sha256 "[a-zA-Z0-9]*"/sha256 "{readable_hash}"/g',
        "idb-companion.rb",
    ],
    cwd=homebrew_fb_repo_path,
    check=True,
)

print(
    bcolors.OKGREEN + "Step 6. " + bcolors.ENDC + "Printing changes of idb-companion.rb"
)
subprocess.run(["git", "--no-pager", "diff"], cwd=homebrew_fb_repo_path, check=True)

print(
    bcolors.HEADER
    + f"Please check {idb_companion_homebrew_config} contents and push the file manually. This script won't do that."
    + bcolors.ENDC
)
print("Yayy, we almost done!")

print("Steps:")
print("1. Review git diff")
print("2. git add idb-companion.rb")
print(f'3. git commit -m "idb v{release}" && git push')
