#!/usr/bin/env bash

rm -rf build

set -e
set -o pipefail

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

xcrun xcodebuild -target XCTestBootstrap | $XC_PIPE
xcrun xcodebuild -target FBSimulatorControl | $XC_PIPE
xcrun xcodebuild -target FBDeviceControl | $XC_PIPE
xcrun xcodebuild -target FBControlCore | $XC_PIPE
