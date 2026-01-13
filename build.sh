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

GRPC_SWIFT_VERSION="1.23.1"
GRPC_SWIFT_DIR="$BUILD_DIRECTORY/grpc-swift"

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

function check_protobuf() {
  local missing=()

  if ! command -v protoc &> /dev/null; then
    missing+=("protoc")
  fi
  if ! command -v protoc-gen-swift &> /dev/null; then
    missing+=("protoc-gen-swift")
  fi

  if [ ${#missing[@]} -ne 0 ]; then
    echo "error: Missing protobuf tools: ${missing[*]}"
    echo "Install with: brew install protobuf swift-protobuf"
    exit 1
  fi
}

function build_grpc_swift_plugin() {
  # Build protoc-gen-grpc-swift from grpc-swift 1.x source
  local plugin_path="$GRPC_SWIFT_DIR/.build/release/protoc-gen-grpc-swift"

  if [ -x "$plugin_path" ]; then
    echo "protoc-gen-grpc-swift already built at $plugin_path"
    return 0
  fi

  echo "Building protoc-gen-grpc-swift from grpc-swift $GRPC_SWIFT_VERSION..."

  if [ ! -d "$GRPC_SWIFT_DIR" ]; then
    echo "Cloning grpc-swift $GRPC_SWIFT_VERSION..."
    git clone --depth 1 --branch "$GRPC_SWIFT_VERSION" \
      https://github.com/grpc/grpc-swift.git "$GRPC_SWIFT_DIR"
  fi

  echo "Building protoc-gen-grpc-swift (this may take a few minutes)..."
  (cd "$GRPC_SWIFT_DIR" && swift build -c release --product protoc-gen-grpc-swift)

  if [ ! -x "$plugin_path" ]; then
    echo "error: Failed to build protoc-gen-grpc-swift"
    exit 1
  fi

  echo "Successfully built protoc-gen-grpc-swift"
}

function generate_proto() {
  check_protobuf
  build_grpc_swift_plugin

  local proto_dir="proto"
  local output_dir="IDBGRPCSwift"
  local protoc=$(which protoc)
  local swift_plugin=$(which protoc-gen-swift)
  local grpc_plugin="$GRPC_SWIFT_DIR/.build/release/protoc-gen-grpc-swift"

  echo "Generating gRPC Swift from proto..."
  mkdir -p "$output_dir"

  $protoc \
    --proto_path="$proto_dir" \
    --swift_out=Visibility=Public:"$output_dir" \
    --grpc-swift_out=Visibility=Public:"$output_dir" \
    --plugin=protoc-gen-grpc-swift="$grpc_plugin" \
    --plugin=protoc-gen-swift="$swift_plugin" \
    "$proto_dir/idb.proto"

  echo "Generated gRPC Swift files in $output_dir"
}

function regenerate_projects() {
  check_xcodegen

  echo "Generating FBSimulatorControl project from project.yml..."
  generate_xcodeproj "." "FBSimulatorControl"
  echo "Generating Shimulator project..."
  generate_xcodeproj "Shims/Shimulator" "Shimulator"
  echo "Generating idb_companion project..."
  generate_xcodeproj "idb_companion" "idb_companion"
}

# =============================================================================
# Build Utilities
# =============================================================================

function invoke_xcodebuild() {
  local arguments=$@
  # Add -skipMacroValidation to work around sandbox restrictions on Swift macro plugins
  # Add ENABLE_USER_SCRIPT_SANDBOXING=NO to disable sandbox for macros
  if [[ -n $HAS_XCPRETTY ]]; then
    NSUnbufferedIO=YES xcodebuild -skipMacroValidation ENABLE_USER_SCRIPT_SANDBOXING=NO $arguments | xcpretty -c
  else
    xcodebuild -skipMacroValidation ENABLE_USER_SCRIPT_SANDBOXING=NO $arguments
  fi
}

function build_idb_deps() {
  if [ -n "$CUSTOM_idb_DEPS_SCRIPT" ]; then
    "$CUSTOM_idb_DEPS_SCRIPT"
  fi
}

function strip_framework() {
  local FRAMEWORK_PATH="$BUILD_DIRECTORY/Build/Products/Release/$1"
  if [ -d "$FRAMEWORK_PATH" ]; then
    echo "Stripping Framework $FRAMEWORK_PATH"
    rm -r "$FRAMEWORK_PATH"
  fi
}

function strip_embedded_frameworks() {
  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "XCTestBootstrap.framework/Versions/Current/Frameworks/FBControlCore.framework"
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
  build_target FBSimulatorControl
  build_target FBDeviceControl
}

function build_shim() {
  local name=$1
  local sdk=$2

  invoke_xcodebuild \
    ONLY_ACTIVE_ARCH=NO \
    -project Shims/Shimulator/Shimulator.xcodeproj \
    -scheme $name \
    -sdk $sdk \
    -derivedDataPath $BUILD_DIRECTORY \
    -configuration Release \
    build
}

function build_shims() {
  build_shim Shimulator iphonesimulator
  build_shim Maculator macosx
}

function build_idb_companion() {
  check_protobuf
  build_idb_deps
  # Ensure proto files are generated
  if [ ! -f "IDBGRPCSwift/idb.grpc.swift" ] || [ ! -f "IDBGRPCSwift/idb.pb.swift" ]; then
    echo "Proto files not found, generating..."
    generate_proto
  fi
  # Build frameworks first in Release (idb_companion depends on them and is built in Release)
  build_target FBControlCore Release
  build_target XCTestBootstrap Release
  build_target FBSimulatorControl Release
  build_target FBDeviceControl Release
  build_target CompanionLib Release
  build_target IDBCompanionUtilities Release
  # Build idb_companion from its own project
  invoke_xcodebuild \
    ONLY_ACTIVE_ARCH=NO \
    -project idb_companion/idb_companion.xcodeproj \
    -scheme idb_companion \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    -configuration Release \
    build
  strip_embedded_frameworks
}

function build_all() {
  # build_idb_companion already builds frameworks first
  build_shims
  build_idb_companion
}

function build() {
  local target=$1

  if [[ -z $target ]]; then
    echo "Building all targets..."
    build_all
  else
    case $target in
      all)
        build_all;;
      frameworks)
        build_all_frameworks;;
      shims)
        build_shims;;
      Shimulator)
        build_shim Shimulator iphonesimulator;;
      Maculator)
        build_shim Maculator macosx;;
      idb_companion)
        build_idb_companion;;
      FBControlCore|XCTestBootstrap|FBSimulatorControl|FBDeviceControl)
        build_target $target;;
      *)
        echo "Unknown target: $target"
        echo "Valid targets: all, frameworks, shims, idb_companion, FBControlCore, XCTestBootstrap, FBSimulatorControl, FBDeviceControl, Shimulator, Maculator"
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
  test_target FBSimulatorControl
  test_target FBDeviceControl
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
      FBControlCore|XCTestBootstrap|FBSimulatorControl|FBDeviceControl)
        test_target $target;;
      *)
        echo "Unknown test target: $target"
        echo "Valid targets: all, FBControlCore, XCTestBootstrap, FBSimulatorControl, FBDeviceControl"
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

  generate-proto
    Regenerate gRPC Swift files from proto/idb.proto.
    This builds protoc-gen-grpc-swift from grpc-swift 1.x source if needed.

  build [<target>]
    Build targets. If no target specified, builds everything.
    Targets:
      (none)          Build all targets
      all             Build all targets
      frameworks      Build all frameworks only
      shims           Build Shimulator and Maculator dylibs
      idb_companion   Build idb_companion only
      FBControlCore   Build FBControlCore framework
      XCTestBootstrap Build XCTestBootstrap framework
      FBSimulatorControl Build FBSimulatorControl framework
      FBDeviceControl Build FBDeviceControl framework
      Shimulator      Build Shimulator dylib (iOS simulator)
      Maculator       Build Maculator dylib (macOS)

  test [<target>]
    Run tests. If no target specified, runs all tests.
    Targets:
      (none)          Run all tests
      all             Run all tests
      FBControlCore   Test FBControlCore
      XCTestBootstrap Test XCTestBootstrap
      FBSimulatorControl Test FBSimulatorControl
      FBDeviceControl Test FBDeviceControl

Examples:
  ./build.sh generate                 # Regenerate Xcode projects
  ./build.sh generate-proto           # Regenerate gRPC Swift from proto
  ./build.sh build                    # Build everything
  ./build.sh build frameworks         # Build all frameworks
  ./build.sh build shims              # Build Shimulator and Maculator
  ./build.sh build idb_companion      # Build idb_companion
  ./build.sh build FBControlCore      # Build specific framework
  ./build.sh test                     # Run all tests
  ./build.sh test FBSimulatorControl  # Test specific framework

Prerequisites:
  - Xcode 14.0+
  - XcodeGen: brew install xcodegen
  - For idb_companion: brew install protobuf swift-protobuf
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
  generate-proto)
    generate_proto;;
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
