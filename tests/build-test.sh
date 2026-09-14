#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

# Covers build.sh's manifest guard and its protoc-plugin checkout selection.
#
# Everything build.sh shells out to for these paths -- git, swift, xattr -- is
# stubbed, so this needs neither the network nor a Swift toolchain. The git stub
# logs the tag it was asked for, which is what lets a case assert *which*
# revision a plugin was built from rather than merely that one exists.
#
# build.sh is a macOS script, so this has to run on a developer's Mac as well as
# on the Linux CI host: no `sed -i` without an argument, no negative array
# subscripts, nothing else past bash 3.2.
#
# $1 is the idb Source directory. Nothing under it is written to: the mutation
# cases run against synthetic manifests, so a real pin bump cannot break them.

set -u

SRC="$1"
if [ ! -f "$SRC/build.sh" ]; then
    echo "error: no build.sh at $SRC" >&2
    exit 1
fi

FAILURES=0

# <description> <expected> <actual>
function assert_equal() {
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected: $2"
        echo "     actual:   $3"
        FAILURES=$((FAILURES + 1))
    fi
}

# <description> <haystack> <needle>
function assert_contains() {
    if printf '%s' "$2" | grep -qF -- "$3"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "     expected to find: $3"
        echo "     in:               $2"
        FAILURES=$((FAILURES + 1))
    fi
}

# Checked before the trap is installed: an unset WORK would send every mkdir
# below to an absolute path outside the sandbox and make the cleanup `rm -rf ""`.
WORK=$(mktemp -d)
if [ -z "${WORK:-}" ] || [ ! -d "$WORK" ]; then
    echo "error: could not create a working directory" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# <sed expression> <file>. GNU and BSD sed disagree about what -i takes, so the
# cases edit through a temporary rather than in place.
function sed_inplace() {
    sed "$1" "$2" > "$2.edited" && mv "$2.edited" "$2"
}

# <file> <line to match on> <text to insert above it>. `sed i\` is spelled
# differently by GNU and BSD sed, so insertion goes through awk instead.
function insert_before() {
    awk -v needle="$2" -v text="$3" 'index($0, needle) { print text } { print }' "$1" \
        > "$1.edited" && mv "$1.edited" "$1"
}

mkdir -p "$WORK/stubs"

# Succeeding means build.sh keeps its build directory inside the package, which
# is what confines this test to $WORK.
cat > "$WORK/stubs/xattr" <<'STUB'
#!/bin/bash
exit 0
STUB

# Records the tag of every clone, so a case can tell a fresh checkout from a
# reused one. Produces a directory and nothing else; the swift stub builds.
cat > "$WORK/stubs/git" <<'STUB'
#!/bin/bash
branch=""
args=("$@")
for i in "${!args[@]}"; do
    [ "${args[$i]}" = "--branch" ] && branch="${args[$((i + 1))]}"
done
dest="${args[$((${#args[@]} - 1))]}"
echo "clone $branch -> $dest" >> "$GIT_STUB_LOG"
mkdir -p "$dest"
STUB

# `swift build -c release --product X`, run from inside the checkout.
cat > "$WORK/stubs/swift" <<'STUB'
#!/bin/bash
product=""
args=("$@")
for i in "${!args[@]}"; do
    [ "${args[$i]}" = "--product" ] && product="${args[$((i + 1))]}"
done
mkdir -p .build/release
printf '#!/bin/sh\n' > ".build/release/$product"
chmod +x ".build/release/$product"
STUB

chmod +x "$WORK/stubs"/*

# <dir> <grpc-swift version> <swift-protobuf version>. A package the pin guard
# accepts: every dependency exact, and the three manifests in agreement.
function write_package() {
    local dir="$1" grpc="$2" protobuf="$3"
    mkdir -p "$dir/Companion"
    cat > "$dir/Package.swift" <<EOF
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "idb",
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", exact: "$grpc"),
        .package(url: "https://github.com/apple/swift-protobuf.git", exact: "$protobuf"),
    ]
)
EOF
    cat > "$dir/Companion/project.yml" <<EOF
name: idb_companion
packages:
  grpc-swift:
    url: https://github.com/grpc/grpc-swift.git
    exactVersion: $grpc
  swift-protobuf:
    url: https://github.com/apple/swift-protobuf.git
    exactVersion: $protobuf
targets:
  idb_companion:
    type: tool
EOF
    cat > "$dir/Package.resolved" <<EOF
{
  "originHash" : "0000000000000000000000000000000000000000000000000000000000000000",
  "pins" : [
    {
      "identity" : "grpc-swift",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/grpc/grpc-swift.git",
      "state" : {
        "revision" : "1111111111111111111111111111111111111111",
        "version" : "$grpc"
      }
    },
    {
      "identity" : "swift-protobuf",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/apple/swift-protobuf.git",
      "state" : {
        "revision" : "2222222222222222222222222222222222222222",
        "version" : "$protobuf"
      }
    }
  ],
  "version" : 3
}
EOF
}

# <case name> <grpc-swift version> <swift-protobuf version>. A package under
# $WORK to mutate, with build.sh alongside it. Echoes the directory.
function stage_package() {
    write_package "$WORK/$1" "$2" "$3"
    cp "$SRC/build.sh" "$WORK/$1/"
    echo "$WORK/$1"
}

# <dir> <shell to run with build.sh sourced>. Runs in the package directory with
# only the stubs on PATH, so anything not stubbed is a hard failure rather than
# a silent call out to the host.
function in_package() {
    local dir="$1" script="$2"
    (
        cd "$dir" || exit 1
        PATH="$WORK/stubs:/usr/bin:/bin"
        # shellcheck disable=SC1090,SC1091
        source ./build.sh
        setup_build_directory > /dev/null
        eval "$script"
    ) 2>&1
}

# <description> <package dir>. A guard case is two assertions in both
# directions: what the guard decided, and what it said. A message with a zero
# status is not a refusal, and a status with no message leaves the developer
# nothing to act on.
function assert_accepted() {
    local output status
    output="$(in_package "$2" 'check_package_pins && echo "pins agree"')"
    status=$?
    assert_equal "$1: the build continues" 0 "$status"
    assert_contains "$1: nothing is reported" "$output" "pins agree"
}

# <description> <package dir> <expected error>
function assert_rejected() {
    local output status
    output="$(in_package "$2" 'check_package_pins')"
    status=$?
    assert_equal "$1: the build stops" 1 "$status"
    assert_contains "$1: the error says what to fix" "$output" "$3"
}

# ---------------------------------------------------------------------------
# Sourcing build.sh has no side effects of its own
# ---------------------------------------------------------------------------

mkdir -p "$WORK/bare"
cp "$SRC/build.sh" "$WORK/bare/build.sh"
output="$(cd "$WORK/bare" && bash -c 'source ./build.sh; echo "sourced"' 2>&1)"
assert_equal "build.sh sources cleanly with no manifests present" "sourced" "$output"
assert_equal "sourcing creates nothing" "build.sh" "$(ls "$WORK/bare")"

# ---------------------------------------------------------------------------
# The pin guard, against the manifests actually checked in
# ---------------------------------------------------------------------------

mkdir -p "$WORK/real/Companion"
cp "$SRC/build.sh" "$SRC/Package.swift" "$SRC/Package.resolved" "$WORK/real/"
cp "$SRC/Companion/project.yml" "$WORK/real/Companion/"

assert_accepted "the checked-in manifests" "$WORK/real"

# ---------------------------------------------------------------------------
# The pin guard, against manifests made to disagree
# ---------------------------------------------------------------------------

assert_accepted "synthetic manifests in agreement" "$(stage_package synthetic 1.27.5 1.38.1)"

dir="$(stage_package disagree 1.27.5 1.38.1)"
sed_inplace 's/exactVersion: 1.38.1/exactVersion: 1.31.0/' "$dir/Companion/project.yml"
assert_rejected "a companion pinned to a different version" "$dir" \
    "swift-protobuf is pinned to 1.38.1 in Package.swift but to 1.31.0 in Companion/project.yml"

dir="$(stage_package floating 1.27.5 1.38.1)"
sed_inplace 's/exact: "1.38.1"/from: "1.38.1"/' "$dir/Package.swift"
assert_rejected "a floating requirement in Package.swift" "$dir" \
    "Package.swift does not pin these to an exact version: swift-protobuf"

# The companion's own exactness arm: XcodeGen would resolve this to whatever the
# package's default branch points at, which is not a pin at all.
dir="$(stage_package unpinned-companion 1.27.5 1.38.1)"
sed_inplace '/exactVersion: 1.38.1/d' "$dir/Companion/project.yml"
assert_rejected "a companion entry with no version" "$dir" \
    "Companion/project.yml does not pin these to an exact version: swift-protobuf"

# Package.resolved is the arm that covers the transitive graph: the two hand-
# written manifests can agree with each other and still both disagree with what
# SwiftPM last resolved.
dir="$(stage_package resolved-drift 1.27.5 1.38.1)"
sed_inplace 's/"version" : "1.38.1"/"version" : "1.31.0"/' "$dir/Package.resolved"
assert_rejected "a Package.resolved recording a different version" "$dir" \
    "swift-protobuf is pinned to 1.38.1 in Package.swift but Package.resolved records 1.31.0"

dir="$(stage_package resolved-absent 1.27.5 1.38.1)"
cat > "$dir/Package.resolved" <<'EOF'
{
  "originHash" : "0000000000000000000000000000000000000000000000000000000000000000",
  "pins" : [
    {
      "identity" : "grpc-swift",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/grpc/grpc-swift.git",
      "state" : {
        "revision" : "1111111111111111111111111111111111111111",
        "version" : "1.27.5"
      }
    }
  ],
  "version" : 3
}
EOF
assert_rejected "a pinned package missing from Package.resolved" "$dir" \
    "swift-protobuf is pinned in Package.swift but absent from Package.resolved"

# Absence is an error on the companion side too. The companion declares packages
# Package.swift only picks up transitively, so the resolved graph is the only
# thing left that can check them -- letting one that is not in it through would
# leave that pin asserted against nothing at all.
dir="$(stage_package resolved-absent-companion 1.27.5 1.38.1)"
insert_before "$dir/Companion/project.yml" "targets:" "  swift-log:
    url: https://github.com/apple/swift-log.git
    exactVersion: 1.14.0"
assert_rejected "a companion-only package missing from Package.resolved" "$dir" \
    "swift-log is pinned in Companion/project.yml but absent from Package.resolved"

# A commented-out dependency declares nothing. Counting one is worse than a
# nuisance: the guard names a package the developer cannot find a requirement
# for, because there is not one.
dir="$(stage_package commented-out 1.27.5 1.38.1)"
insert_before "$dir/Package.swift" ".package(url: \"https://github.com/grpc/grpc-swift.git\"" \
    "        // .package(url: \"https://github.com/apple/swift-nio.git\", from: \"2.50.0\"),"
assert_accepted "a commented-out dependency in Package.swift" "$dir"

# XcodeGen accepts `version:` as a synonym for `exactVersion:`, so a companion
# spelled that way is pinned and must read as pinned.
dir="$(stage_package version-spelling 1.27.5 1.38.1)"
sed_inplace 's/    exactVersion: 1.38.1/    version: 1.38.1/' "$dir/Companion/project.yml"
assert_accepted "a companion pinned with version rather than exactVersion" "$dir"

# An entry in flow form is one the parser genuinely cannot read. It matches no
# entry header, so it falls out of the pinned and the unpinned listing alike --
# and a package in neither listing is a package nothing above checks.
dir="$(stage_package flow-form 1.27.5 1.38.1)"
insert_before "$dir/Companion/project.yml" "targets:" \
    "  swift-log: {url: https://github.com/apple/swift-log.git, exactVersion: 1.14.0}"
assert_rejected "a companion entry written in flow form" "$dir" \
    "Companion/project.yml declares these in a form this check cannot read: swift-log"

# The same hole on the Package.swift side. SwiftPM accepts a .package(...) split
# over several lines, and a split one matches neither extractor -- so it too
# falls out of both listings. Nothing on the line names the package, so the
# refusal is keyed on where it is rather than on what it is called.
dir="$(stage_package split-declaration 1.27.5 1.38.1)"
insert_before "$dir/Package.swift" "    ]" "        .package(
            url: \"https://github.com/apple/swift-nio.git\",
            from: \"2.50.0\"
        ),"
assert_rejected "a Package.swift dependency split over several lines" "$dir" \
    "Package.swift declares dependencies this check cannot read, on lines: 9"

# ---------------------------------------------------------------------------
# Which revision the plugin is actually built from
# ---------------------------------------------------------------------------

dir="$(stage_package plugin 1.27.5 1.38.1)"
export GIT_STUB_LOG="$WORK/plugin.gitlog"
: > "$GIT_STUB_LOG"

# The tags cloned so far, in order -- the checkout paths are temporary and the
# tag is the whole question.
function cloned_tags() {
    awk '{ printf "%s%s", (NR > 1 ? " " : ""), $2 } END { print "" }' "$GIT_STUB_LOG"
}

output="$(in_package "$dir" 'build_grpc_swift_plugin')"
status=$?
assert_equal "a cold checkout builds the plugin" 0 "$status"
assert_contains "and reports it built" "$output" "Successfully built protoc-gen-grpc-swift"
assert_equal "from the pinned tag" "1.27.5" "$(cloned_tags)"

in_package "$dir" 'build_grpc_swift_plugin' > /dev/null
status=$?
assert_equal "a warm checkout at the same pin still succeeds" 0 "$status"
assert_equal "and is not re-cloned" "1.27.5" "$(cloned_tags)"

# The pin moves, both manifests move with it, and the guard is satisfied -- so
# nothing before the plugin builder can notice that the checkout on disk was
# built from the previous tag.
write_package "$dir" 1.28.0 1.38.1
in_package "$dir" 'build_grpc_swift_plugin' > /dev/null
status=$?
assert_equal "a bumped pin still succeeds" 0 "$status"

# BUG: the checkout directory carries no version, so the plugin built at 1.27.5
# is reused for a package now pinned to 1.28.0 -- flipped in the following commit.
assert_equal "a bumped pin reuses the checkout built at the old tag" \
    "1.27.5" "$(cloned_tags)"

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES assertion(s) failed"
    exit 1
fi

echo "all assertions passed"
