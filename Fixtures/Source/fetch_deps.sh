#!/bin/bash
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -ex

SCRIPT="$(realpath "$0")"
SCRIPTPATH="$(dirname "$SCRIPT")"
RUNNER_FRAMEWORK_DIR="$SCRIPTPATH/FBTestRunnerApp/Frameworks"
XCODE_PATH=$(xcode-select -p)

if [ ! -d "$RUNNER_FRAMEWORK_DIR" ]; then
  mkdir "$RUNNER_FRAMEWORK_DIR"
fi

rm -rf "${RUNNER_FRAMEWORK_DIR:-}/*"
cp -rf "$XCODE_PATH/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks/XCTest.framework" "$RUNNER_FRAMEWORK_DIR"
cp -rf "$XCODE_PATH/Platforms/iPhoneSimulator.platform/Developer/Library/PrivateFrameworks/XCTAutomationSupport.framework" "$RUNNER_FRAMEWORK_DIR"
