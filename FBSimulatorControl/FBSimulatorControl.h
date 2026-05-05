/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Headers with C type definitions must come before any header that imports
// FBSimulatorControl-Swift.h, because the generated Swift header may reference
// these types (e.g. FBSimulatorBootOptions).
#import <FBSimulatorControl/FBFramebuffer.h>
#import <FBSimulatorControl/FBSimDeviceWrapper.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorAccessibilityCommands.h>
#import <FBSimulatorControl/FBSimulatorBootConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControlFrameworkLoader.h>
#import <FBSimulatorControl/FBSimulatorHID.h>
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>
#import <FBSimulatorControl/FBSimulatorPurpleHID.h>
#import <FBSimulatorControl/FBSimulatorVideoStream.h>

#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
