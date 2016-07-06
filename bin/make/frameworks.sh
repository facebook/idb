#!/usr/bin/env bash

rm -rf build
xcodebuild -target FBSimulatorControl
xcodebuild -target FBDeviceControl
xcodebuild -target FBControlCore
xcodebuild -target XCTestBootstrap
