#!/bin/bash

set -e

BUILD_DIRECTORY=build

function assert_has_carthage() {
  if ! command -v carthage; then
      echo "build needs 'carthage' to bootstrap dependencies"
      echo "You can install it using brew. E.g. $ brew install carthage"
      exit 1;
  fi
}

function build_fbsimctl_deps() {
  assert_has_carthage
  pushd fbsimctl
  carthage bootstrap --platform Mac
  popd
}

function build_test_deps() {
  assert_has_carthage
  carthage bootstrap --platform Mac
}

function framework_build() {
  local name=$1
  xcodebuild \
    -project FBSimulatorControl.xcodeproj \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build

  local output_directory=$2
  if [[ -n $output_directory ]]; then
    local artifact="$BUILD_DIRECTORY/Build/Products/Debug/$name.framework"
    echo "Copying Build output from $artifact to $output_directory"
    mkdir -p "$output_directory"
    cp -R $artifact "$output_directory"
  fi
}

function framework_test() {
  local name=$1
  xctool \
    -project FBSimulatorControl.xcodeproj \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function core_framework_build() {
  framework_build FBControlCore $1
}

function core_framework_test() {
  framework_test FBControlCore
}

function xctest_framework_build() {
  framework_build XCTestBootstrap $1
}

function xctest_framework_test() {
  framework_test XCTestBootstrap
}

function simulator_framework_build() {
  framework_build FBSimulatorControl $1
}

function simulator_framework_test() {
  framework_test FBSimulatorControl
}

function device_framework_build() {
  framework_build FBDeviceControl $1
}

function device_framework_test() {
  framework_test FBDeviceControl
}

function all_frameworks_build() {
  local output_directory=$1
  core_framework_build $output_directory
  xctest_framework_build $output_directory
  simulator_framework_build $output_directory
  device_framework_build $output_directory
}

function all_frameworks_test() {
  core_framework_test
  xctest_framework_test
  simulator_framework_test
  device_framework_test
}

function strip_framework() {
  local FRAMEWORK_PATH="$BUILD_DIRECTORY/Build/Products/Debug/$1"
  if [ -d "$FRAMEWORK_PATH" ]; then
    echo "Stripping Framework $FRAMEWORK_PATH"
    rm -r "$FRAMEWORK_PATH"
  fi
}

function cli_build() {
  local name=$1
  xcodebuild \
    -workspace $name/$name.xcworkspace \
    -scheme $name \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    build

  strip_framework "FBSimulatorControlKit.framework/Versions/Current/Frameworks/FBSimulatorControl.framework"
  strip_framework "FBSimulatorControlKit.framework/Versions/Current/Frameworks/FBDeviceControl.framework"
  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
  strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
  strip_framework "XCTestBootstrap.framework/Versions/Current/Frameworks/FBControlCore.framework"

  local output_directory=$2
  if [[ -n $output_directory ]]; then
    local artifact="$BUILD_DIRECTORY/Build/Products/Debug/*"
    echo "Copying Build output from $artifact to $output_directory"
    mkdir -p "$output_directory"
    cp -R $artifact "$output_directory"
  fi
}

function cli_framework_test() {
  NAME=$1
  xctool \
    -workspace $NAME/$NAME.xcworkspace \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function cli_e2e_test() {
  NAME=$1
  pushd $NAME/cli-tests
  ./tests.py
  popd
}

function print_usage() {
cat <<EOF
./build.sh usage:
  /build.sh <target> <command> [<arg>]*

Supported Commands:
  help
    Print usage.
  framework build <output-directory>
    Build the FBSimulatorControl.framework. Optionally copies the Framework to <output-directory>
  framework test
    Build then Test the FBSimulatorControl.framework. Requires xctool to be installed.
  fbsimctl build <output-directory>
    Build the fbsimctl exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  fbsimctl test
    Build the FBSimulatorControlKit.framework and runs the tests. Requires xctool to be installed.
  fbsimctl e2e-test
    Build the fbsimctl executable and run the e2e CLI Tests against it. Requires python3
  fbxctest build <output-directory>
    Build the xctest exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  fbxctest test
    Builds the FBXCTestKit.framework and runs the tests. Requires xctool to be installed.
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
      test)
        build_test_deps
        all_frameworks_test;;
      *)
        echo "Unknown Command $2"
        exit 1;;
    esac;;
  fbsimctl)
    build_fbsimctl_deps
    case $COMMAND in
      build)
        cli_build fbsimctl $OUTPUT_DIRECTORY;;
      test)
        build_test_deps
        cli_framework_test fbsimctl;;
      e2e-test)
        cli_build fbsimctl fbsimctl/cli-tests/executable-under-test
        cli_e2e_test fbsimctl;;
      *)
        echo "Unknown Command $COMMAND"
        exit 1;;
    esac;;
  fbxctest)
    case $COMMAND in
      build)
        cli_build fbxctest $OUTPUT_DIRECTORY;;
      test)
        build_test_deps
        cli_framework_test fbxctest;;
      *)
        echo "Unknown Command $COMMAND"
        exit 1;;
    esac;;
  *)
    echo "Unknown Command $TARGET"
    exit 1;;
esac

# vim: set tabstop=2 shiftwidth=2 filetype=sh:
