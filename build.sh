#!/bin/bash

set -e

BUILD_DIRECTORY=build
CLI_E2E_PATH=fbsimctl/cli-tests/executable-under-test

function assert_xcode_version() {
  local version=$1
  if ! xcodebuild -version | grep -q "Xcode $version\."; then
    echo "building fbsimctl requires Xcode $version"
    exit 1
  fi
}

function assert_has_carthage() {
  if ! command -v carthage; then
      echo "build needs 'carthage' to bootstrap dependencies"
      echo "You can install it using brew. E.g. $ brew install carthage"
      exit 1;
  fi
}

function build_fbsimctl_deps() {
  assert_xcode_version 8
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
  local output_directory=$2

  xcodebuild \
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

function framework_test() {
  local name=$1
  xcodebuild \
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
  local output_directory=$2
  local script_directory=$1/Scripts

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

  if [[ -n $output_directory ]]; then
    cli_install $output_directory $script_directory
  fi
}

function cli_install() {
  local output_directory=$1
  local script_directory=$2
  local cli_artifact="$BUILD_DIRECTORY/Build/Products/Debug/!(*.framework)"
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

function cli_framework_test() {
  NAME=$1
  xcodebuild \
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
    Build then Test the FBSimulatorControl.framework.
  fbsimctl build <output-directory>
    Build the fbsimctl exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  fbsimctl test
    Build the FBSimulatorControlKit.framework and runs the tests.
  fbsimctl e2e-test
    Build the fbsimctl executable and run the e2e CLI Tests against it. Requires python3
  fbxctest build <output-directory>
    Build the xctest exectutable. Optionally copies the executable and it's dependencies to <output-directory>
  fbxctest test
    Builds the FBXCTestKit.framework and runs the tests.
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
        rm -r "$CLI_E2E_PATH" || true
        cli_build fbsimctl "$CLI_E2E_PATH"
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
