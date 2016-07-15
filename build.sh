#!/bin/bash

set -e
set -x

BUILD_DIRECTORY=build

function assert_has_carthage() {
  if ! command -v carthage; then
      echo "cli build needs 'carthage' to bootstrap dependencies"
      echo "You can install it using brew. E.g. $ brew install carthage"
      exit 1;
  fi
}

function build_cli_deps() {
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
    ARTIFACT="$BUILD_DIRECTORY/Build/Products/Debug/$NAME.framework"
    echo "Copying Build output from $ARTIFACT to $output_directory"
    mkdir -p $output_directory
    cp -r $ARTIFACT $output_directory
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
  framework_build FBControlCore
}

function core_framework_test() {
  framework_test FBControlCore
}

function xctest_framework_build() {
  framework_build XCTestBootstrap
}

function xctest_framework_test() {
  framework_test XCTestBootstrap
}

function simulator_framework_build() {
  framework_build FBSimulatorControl
}

function simulator_framework_test() {
  framework_test FBSimulatorControl
}

function device_framework_build() {
  framework_build FBDeviceControl
}

function device_framework_test() {
  framework_test FBDeviceControl
}

function all_frameworks_build() {
  core_framework_build
  xctest_framework_build
  simulator_framework_build
  device_framework_build
}

function all_frameworks_test() {
  core_framework_test
  xctest_framework_test
  simulator_framework_test
  device_framework_test
}

function strip_framework() {
  local FRAMEWORK_PATH="$BUILD_DIRECTORY/Build/Products/Debug/$1"
  echo "Stripping Framework $FRAMEWORK_PATH"
  rm -r "$FRAMEWORK_PATH"
}

function cli_build() {
  local name=fbsimctl
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
  
  local output_directory=$1
  if [[ -n $output_directory ]]; then
    ARTIFACT="$BUILD_DIRECTORY/Build/Products/Debug/*"
    echo "Copying Build output from $ARTIFACT to $output_directory"
    mkdir -p $output_directory
    cp -r $ARTIFACT $output_directory
  fi
}

function cli_framework_test() {
  NAME=fbsimctl
  xctool \
    -workspace $NAME/$NAME.xcworkspace \
    -scheme $NAME \
    -sdk macosx \
    -derivedDataPath $BUILD_DIRECTORY \
    test
}

function cli_e2e_test() {
  pushd fbsimctl/cli-tests
  python3 -m unittest tests
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
  cli build <output-directory>
    Build the fbsimctl exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  cli test
    Build the FBSimulatorControlKit.framework and runs the tests. Requires xctool to be installed.
  cli e2e-test
    Build the fbsimctl executable and run the e2e CLI Tests against it. Requires python3
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
        all_frameworks_build;;
      test) 
        build_test_deps
        all_frameworks_test;;
      *) 
        echo "Unknown Command $2"
        exit 1;;
    esac;;
  cli)
    build_cli_deps
    case $COMMAND in
      build) 
        cli_build;;
      test)
        build_test_deps
        cli_framework_test;;
      e2e-test)
        cli_build fbsimctl/cli-tests/executable-under-test
        cli_e2e_test;;
      *)
        echo "Unknown Command $COMMAND"
        exit 1;;
    esac;;
  *) 
    echo "Unknown Command $TARGET"
    exit 1;;
esac

# vim: set tabstop=2 shiftwidth=2 filetype=sh:
