#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -euo pipefail

app=$1
distribution=$2
repl=$3
remote=$4
destination=$5

ditto --noextattr "$app" "$destination"
# Buck can materialize the input bundle read-only.
chmod -R u+w "$destination"
contents="$destination/Contents"
executable=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$contents/Info.plist")
if [ "$executable" != simscope ]; then
  mv "$contents/MacOS/$executable" "$contents/MacOS/simscope"
  /usr/libexec/PlistBuddy -c 'Set CFBundleExecutable simscope' "$contents/Info.plist"
fi
ditto --noextattr "$distribution/Resources" "$contents/Resources"
cp "$(dirname "$0")/../../LICENSE" "$contents/Resources/LICENSE"
cp "$distribution/idb_companion" "$contents/MacOS/idb_companion"
cp "$repl" "$contents/MacOS/idb-repl"
cp "$remote" "$contents/MacOS/simscope-remote"
# SwiftPM resolves resource bundles relative to Bundle.main; standalone helpers
# can instead resolve relative to their executable directory.
for bundle in "$distribution"/*.bundle; do
  [ -d "$bundle" ] || continue
  ditto --noextattr "$bundle" "$contents/Resources/$(basename "$bundle")"
  ln -s "../Resources/$(basename "$bundle")" "$contents/MacOS/$(basename "$bundle")"
done
ln -s ../Resources "$contents/MacOS/Resources"
for tool in simscope idb_companion idb-repl simscope-remote; do
  chmod u+w,a+x "$contents/MacOS/$tool"
  codesign --force --sign - --timestamp=none "$contents/MacOS/$tool"
done
codesign --force --sign - --timestamp=none "$destination"
codesign --verify --deep --strict "$destination"
