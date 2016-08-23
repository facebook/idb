#!/usr/bin/env bash

rm -rf build

set -e

if [[ "${SHELL}" =~ "zsh" ]]; then
  echo "-o pipefail is not available in zsh.  You have been warned."
else
  set -o pipefail
fi

if [ "${XCPRETTY}" = "0" ]; then
  USE_XCPRETTY=
else
  USE_XCPRETTY=`which xcpretty | tr -d '\n'`
fi

if [ ! -z ${USE_XCPRETTY} ]; then
  XC_PIPE='xcpretty -c'
else
  XC_PIPE='cat'
fi

BUILD_DIR="build"
XC_PROJECT="FBSimulatorControl.xcodeproj"

xcrun xcodebuild \
  -SYMROOT="${BUILD_DIR}" \
  -OBJROOT="${BUILD_DIR}" \
  -project ${XC_PROJECT} \
  -target XCTestBootstrap \
  -configuration Release \
  -sdk macosx \
  build | $XC_PIPE

xcrun xcodebuild \
  -SYMROOT="${BUILD_DIR}" \
  -OBJROOT="${BUILD_DIR}" \
  -project ${XC_PROJECT} \
  -target FBSimulatorControl \
  -configuration Release \
  -sdk macosx \
  build | $XC_PIPE

xcrun xcodebuild \
  -SYMROOT="${BUILD_DIR}" \
  -OBJROOT="${BUILD_DIR}" \
  -project ${XC_PROJECT} \
  -target FBDeviceControl \
  -configuration Release \
  -sdk macosx \
  build | $XC_PIPE

xcrun xcodebuild \
  -SYMROOT="${BUILD_DIR}" \
  -OBJROOT="${BUILD_DIR}" \
  -project ${XC_PROJECT} \
  -target FBControlCore \
  -configuration Release \
  -sdk macosx \
  build | $XC_PIPE

