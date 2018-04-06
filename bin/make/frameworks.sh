#!/usr/bin/env bash

source bin/log.sh
source bin/simctl.sh
ensure_valid_core_sim_service

rm -rf build

hash xcpretty 2>/dev/null
if [ $? -eq 0 ] && [ "${XCPRETTY}" != "0" ]; then
  XC_PIPE='xcpretty -c'
else
  XC_PIPE='cat'
fi

info "Will pipe xcodebuild to: ${XC_PIPE}"

set -e -o pipefail

# Legacy directory - remove to avoid confusion.
rm -rf Products/

BUILD_DIR="build"
CONFIGURATION=Release
XC_PROJECT="FBSimulatorControl.xcodeproj"

function strip_framework() {
  local FRAMEWORK_PATH="${BUILD_DIR}/Build/Products/${CONFIGURATION}/${1}"
  if [ -d "$FRAMEWORK_PATH" ]; then
    rm -r "$FRAMEWORK_PATH"
  fi
}

# We would like to use optimization "s".
# Starting in Xcode 9, we started to see bad access at runtime.
# https://github.com/facebook/FBSimulatorControl/issues/425
function framework_build() {
  local target="${1}"
  xcrun xcodebuild \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    ENABLE_TESTABILITY=NO \
    GCC_OPTIMIZATION_LEVEL=0 \
    -SYMROOT="${BUILD_DIR}" \
    -OBJROOT="${BUILD_DIR}" \
    -project "${XC_PROJECT}" \
    -target "${target}" \
    -configuration "${CONFIGURATION}" \
    -sdk macosx \
    build | $XC_PIPE
}

framework_build XCTestBootstrap
framework_build FBSimulatorControl
framework_build FBDeviceControl
framework_build FBControlCore

# See the Frameworks.xcconfig file for why this is necessary.
strip_framework "FBSimulatorControlKit.framework/Versions/Current/Frameworks/FBSimulatorControl.framework"
strip_framework "FBSimulatorControlKit.framework/Versions/Current/Frameworks/FBDeviceControl.framework"
strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
strip_framework "FBSimulatorControl.framework/Versions/Current/Frameworks/CocoaLumberjack.framework"
strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/XCTestBootstrap.framework"
strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/FBControlCore.framework"
strip_framework "FBDeviceControl.framework/Versions/Current/Frameworks/CocoaLumberjack.framework"
strip_framework "XCTestBootstrap.framework/Versions/Current/Frameworks/FBControlCore.framework"
strip_framework "XCTestBootstrap.framework/Versions/Current/Frameworks/CocoaLumberjack.framework"
strip_framework "FBControlCore.framework/Versions/Current/Frameworks/CocoaLumberjack.framework"

osascript -e 'display notification "Finished building FBSimulatorControl" with title "iOSDeviceManager" subtitle "Make"'
