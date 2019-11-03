#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -e
set -o pipefail

if hash xcpretty 2>/dev/null; then
  HAS_XCPRETTY=true
fi

BUILD_DIRECTORY=build

function invoke_xcodebuild() {
  local arguments=$@
  if [[ -n $HAS_XCPRETTY ]]; then
    NSUnbufferedIO=YES xcodebuild $arguments | xcpretty -c
  else
    xcodebuild $arguments
  fi
}

function build_idb_deps() {
  if [ -n "$CUSTOM_idb_DEPS_SCRIPT" ]; then
    "$CUSTOM_idb_DEPS_SCRIPT"
  fi
}

function framework_build() {
  local name=$1
  local output_directory=$2

  invoke_xcodebuild \
    -project FBSimulatorControl.xcodeproj \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build

  if [[ -n $output_directory ]]; then
    framework_install $name $output_directory
  fi
}

function framework_install() {
  local name=$1
  local output_directory=$2
  local artifact="$BUILD_DIRECTORY/Build/Products/Debug/$name.framework"
  local output_directory_framework="$output_directory/Frameworks"

  echo "Copying Build output of $artifact to $output_directory_framework"
  mkdir -p "$output_directory_framework"
  cp -R $artifact "$output_directory_framework/"
}

function core_framework_build() {
  framework_build FBControlCore $1
}

function xctest_framework_build() {
  framework_build XCTestBootstrap $1
}

function simulator_framework_build() {
  framework_build FBSimulatorControl $1
}

function device_framework_build() {
  framework_build FBDeviceControl $1
}

function all_frameworks_build() {
  local output_directory=$1
  core_framework_build $output_directory
  xctest_framework_build $output_directory
  simulator_framework_build $output_directory
  device_framework_build $output_directory
}

function strip_framework() {
  local FRAMEWORK_PATH="$BUILD_DIRECTORY/Build/Products/Debug/$1"
  if [ -d "$FRAMEWORK_PATH" ]; then
    echo "Stripping Framework $FRAMEWORK_PATH"
    rm -r "$FRAMEWORK_PATH"
  fi
}

function strip_idb_grpc() {
  echo "Stripping idbGRPC from $BUILD_DIRECTORY"
  rm -rf $BUILD_DIRECTORY/Build/Products/Debug/*idbGRPC*
}

function cli_build() {
  local name=$1
  local output_directory=$2
  local script_directory=$1/Scripts

  invoke_xcodebuild \
    -workspace $name.xcworkspace \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build

  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "XCTestBootstrap.framework/Versions/Current/Frameworks/FBControlCore.framework"

  if [[ -n $output_directory ]]; then
    cli_install $output_directory $script_directory
  fi
}

function cli_install() {
  local output_directory=$1
  local script_directory=$2
  local cli_artifact="$BUILD_DIRECTORY/Build/Products/Debug/idb_companion"
  local framework_artifact="$BUILD_DIRECTORY/Build/Products/Debug/*.framework"
  local output_directory_cli="$output_directory/bin"
  local output_directory_framework="$output_directory/Frameworks"

  mkdir -p "$output_directory_cli"
  mkdir -p "$output_directory_framework"

  shopt -s extglob

  echo "Copying Build output from $cli_artifact to $output_directory_cli"
  cp -R $cli_artifact "$output_directory_cli"

  echo "Copying Build output from $framework_artifact to $output_directory_framework"
  cp -R $framework_artifact "$output_directory_framework"

  if [[ -d $script_directory ]]; then
    echo "Copying Scripts from $script_directory to $output_directory_cli"
    cp -R "$2"/* "$output_directory_cli"
  fi

  shopt -u extglob
}


function print_usage() {
cat <<EOF
./idb_build.sh usage:
  /idb_build.sh <target> <command> [<arg>]*

Supported Commands:
  help
    Print usage.
  framework build <output-directory>
    Build the frameworks. Optionally copies the Framework to <output-directory>
  idb_companion build <output-directory>
    Build the idb companion exectutable. Optionally copies the executable and its dependencies to <output-directory>
EOF
}

if [[ -n $TARGET ]]; then
  echo "using target $TARGET"
elif [[ -n $1 ]]; then
  TARGET=$1
  echo "using target $TARGET"
else
  echo "No target argument or $TARGET provided"
  print_usage
  exit 1
fi

if [[ -n $COMMAND ]]; then
  echo "using command $COMMAND"
elif [[ -n $2 ]]; then
  COMMAND=$2
  echo "using command $COMMAND"
else
  echo "No command argument or $COMMAND provided"
  print_usage
  exit 1
fi

if [[ -n $OUTPUT_DIRECTORY ]]; then
  echo "using output directory $OUTPUT_DIRECTORY"
elif [[ -n $3 ]]; then
  echo "using output directory $3"
  OUTPUT_DIRECTORY=$3
else
  echo "No output directory specified"
fi

case $TARGET in
  help)
    print_usage;;
  framework)
    case $COMMAND in
      build)
        all_frameworks_build $OUTPUT_DIRECTORY;;
      *)
        echo "Unknown Command $2"
        exit 1;;
    esac;;
  idb_companion)
    build_idb_deps
    case $COMMAND in
      build)
        cli_build idb_companion $OUTPUT_DIRECTORY;;
      *)
        echo "Unknown Command $COMMAND"
        exit 1;;
    esac;;
  *)
    echo "Unknown Command $TARGET"
    exit 1;;
esac

# vim: set tabstop=2 shiftwidth=2 filetype=sh:
