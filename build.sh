#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -e
set -o pipefail

if hash xcpretty 2>/dev/null; then
  HAS_XCPRETTY=true
fi

# Check if xattrs are supported on the current filesystem
# Some virtual filesystems (e.g., EdenFS) don't support xattrs
function supports_xattrs() {
  local test_file=".xattr_test_$$"
  if touch "$test_file" 2>/dev/null && xattr -w com.test.xattr test "$test_file" 2>/dev/null; then
    xattr -d com.test.xattr "$test_file" 2>/dev/null
    rm -f "$test_file"
    return 0
  fi
  rm -f "$test_file" 2>/dev/null
  return 1
}

# Use build directory outside of repo if xattrs not supported (for Xcode compatibility)
if supports_xattrs; then
  BUILD_DIRECTORY=build
else
  BUILD_DIRECTORY="/tmp/idb-build-$(basename "$(pwd)")"
  echo "Note: Using external build directory at $BUILD_DIRECTORY (xattrs not supported)"
fi

# =============================================================================
# XcodeGen Project Generation
# =============================================================================

function check_xcodegen() {
  if ! command -v xcodegen &> /dev/null; then
    echo "error: XcodeGen not found. Install with: brew install xcodegen"
    exit 1
  fi
}

# Check if ditto is available for xattr-free copying
function has_ditto() {
  command -v ditto &> /dev/null
}

# Validate that a generated xcodeproj is valid
# Usage: validate_xcodeproj <xcodeproj_path>
function validate_xcodeproj() {
  local xcodeproj_path="$1"
  local pbxproj="${xcodeproj_path}/project.pbxproj"

  if [ ! -d "$xcodeproj_path" ]; then
    echo "error: Generated project not found at $xcodeproj_path"
    return 1
  fi

  if [ ! -f "$pbxproj" ]; then
    echo "error: project.pbxproj not found in $xcodeproj_path"
    return 1
  fi

  if [ ! -s "$pbxproj" ]; then
    echo "error: project.pbxproj is empty in $xcodeproj_path"
    return 1
  fi

  # Basic validation: check for required Xcode project structure
  if ! grep -q "PBXProject" "$pbxproj"; then
    echo "error: project.pbxproj appears to be invalid (missing PBXProject)"
    return 1
  fi

  return 0
}

# Generate a single xcodeproj, optionally stripping xattrs for filesystem compatibility
# Usage: generate_xcodeproj <project_dir> <project_name>
function generate_xcodeproj() {
  local project_dir="$1"
  local project_name="$2"
  local xcodeproj_name="${project_name}.xcodeproj"
  local dest_path="${project_dir}/${xcodeproj_name}"

  # Default to stripping xattrs for filesystem compatibility
  local strip_xattrs="${XCODEGEN_STRIP_XATTRS:-true}"

  if [[ "$strip_xattrs" == "true" ]] && has_ditto; then
    # Generate to temp dir outside filesystem, then copy without xattrs
    local temp_dir=$(mktemp -d)
    local abs_project_dir
    abs_project_dir=$(cd "$project_dir" && pwd)

    echo "  [xattr workaround] Generating to temp: $temp_dir"
    rm -rf "$dest_path"
    (cd "$project_dir" && xcodegen generate -p "$temp_dir")

    # Fix paths in pbxproj - XcodeGen creates relative paths from temp dir
    # We need to convert these back to paths relative to the project dir
    local pbxproj="${temp_dir}/${xcodeproj_name}/project.pbxproj"
    if [ -f "$pbxproj" ]; then
      # Calculate the wrong relative prefix that XcodeGen created
      # and replace it with correct relative path (empty for same dir)
      local escaped_path
      escaped_path=$(echo "$abs_project_dir/" | sed 's/[\/&]/\\&/g')
      # Replace absolute path references that were made relative from /tmp
      sed -i '' "s|[.][.]/[^;\"]*${escaped_path}||g" "$pbxproj"
      echo "  [xattr workaround] Fixed relative paths in project.pbxproj"
    fi

    # Validate temp project before copying
    if ! validate_xcodeproj "${temp_dir}/${xcodeproj_name}"; then
      echo "error: Generated project failed validation"
      rm -rf "$temp_dir"
      exit 1
    fi

    # Use ditto to copy without xattrs
    echo "  [xattr workaround] Copying to $dest_path (without xattrs)"
    ditto --noextattr "${temp_dir}/${xcodeproj_name}" "$dest_path"
    rm -rf "$temp_dir"

    # Validate final project
    if validate_xcodeproj "$dest_path"; then
      echo "  [xattr workaround] Project validated successfully"
    else
      echo "error: Final project failed validation"
      exit 1
    fi
  else
    # Direct generation
    (cd "$project_dir" && xcodegen generate)
    if ! validate_xcodeproj "$dest_path"; then
      echo "error: Generated project failed validation"
      exit 1
    fi
  fi
}

function regenerate_projects() {
  check_xcodegen

  echo "Generating FBSimulatorControl project from project.yml..."
  generate_xcodeproj "." "FBSimulatorControl"
}

# =============================================================================
# Build Utilities
# =============================================================================

function invoke_xcodebuild() {
  local arguments=$@
  if [[ -n $HAS_XCPRETTY ]]; then
    NSUnbufferedIO=YES xcodebuild -skipMacroValidation $arguments | xcpretty -c
  else
    xcodebuild -skipMacroValidation $arguments
  fi
}

# =============================================================================
# Build Functions
# =============================================================================

function build_target() {
  local name=$1
  local configuration=${2:-Debug}

  invoke_xcodebuild \
    ONLY_ACTIVE_ARCH=NO \
    -project FBSimulatorControl.xcodeproj \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    -configuration $configuration \
    build
}

function build_all_frameworks() {
  build_target FBControlCore
  build_target XCTestBootstrap
}

function build() {
  local target=$1

  if [[ -z $target ]]; then
    echo "Building all targets..."
    build_all_frameworks
  else
    case $target in
      all|frameworks)
        build_all_frameworks;;
      FBControlCore|XCTestBootstrap)
        build_target $target;;
      *)
        echo "Unknown target: $target"
        echo "Valid targets: all, frameworks, FBControlCore, XCTestBootstrap"
        exit 1;;
    esac
  fi
}

# =============================================================================
# Test Functions
# =============================================================================

function test_target() {
  local name=$1
  invoke_xcodebuild \
    -project FBSimulatorControl.xcodeproj \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function test_all() {
  test_target FBControlCore
  test_target XCTestBootstrap
}

function run_tests() {
  local target=$1

  if [[ -z $target ]]; then
    echo "Running all tests..."
    test_all
  else
    case $target in
      all)
        test_all;;
      FBControlCore|XCTestBootstrap)
        test_target $target;;
      *)
        echo "Unknown test target: $target"
        echo "Valid targets: all, FBControlCore, XCTestBootstrap"
        exit 1;;
    esac
  fi
}

# =============================================================================
# Usage
# =============================================================================

function print_usage() {
cat <<EOF
./build.sh - Build script for idb

Usage:
  ./build.sh <command> [<target>]

Commands:
  help
    Print this usage information.

  generate
    Regenerate Xcode projects from project.yml using XcodeGen.

  build [<target>]
    Build targets. If no target specified, builds everything.
    Targets:
      (none)          Build all targets
      all             Build all targets
      frameworks      Build all frameworks only
      FBControlCore   Build FBControlCore framework
      XCTestBootstrap Build XCTestBootstrap framework

  test [<target>]
    Run tests. If no target specified, runs all tests.
    Targets:
      (none)          Run all tests
      all             Run all tests
      FBControlCore   Test FBControlCore
      XCTestBootstrap Test XCTestBootstrap

Examples:
  ./build.sh generate                 # Regenerate Xcode projects
  ./build.sh build                    # Build everything
  ./build.sh build FBControlCore      # Build specific framework
  ./build.sh test                     # Run all tests
  ./build.sh test XCTestBootstrap     # Test specific framework

Prerequisites:
  - Xcode 14.0+
  - XcodeGen: brew install xcodegen
EOF
}

# =============================================================================
# Main
# =============================================================================

COMMAND=${COMMAND:-$1}
TARGET_ARG=${2:-}

if [[ -z $COMMAND ]]; then
  echo "No command provided"
  print_usage
  exit 1
fi

echo "Command: $COMMAND"
if [[ -n $TARGET_ARG ]]; then
  echo "Target: $TARGET_ARG"
fi

case $COMMAND in
  help|-h|--help)
    print_usage;;
  generate)
    regenerate_projects;;
  build)
    regenerate_projects
    build $TARGET_ARG;;
  test)
    regenerate_projects
    run_tests $TARGET_ARG;;
  *)
    echo "Unknown command: $COMMAND"
    print_usage
    exit 1;;
esac

# vim: set tabstop=2 shiftwidth=2 filetype=sh:
