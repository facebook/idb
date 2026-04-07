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
#import <FBSimulatorControl/FBSimulatorApplicationCommands.h>
#import <FBSimulatorControl/FBSimulatorBootConfiguration.h>
#import <FBSimulatorControl/FBSimulatorBridge.h>
#import <FBSimulatorControl/FBSimulatorControlFrameworkLoader.h>
#import <FBSimulatorControl/FBSimulatorError.h>
#import <FBSimulatorControl/FBSimulatorFileCommands.h>
#import <FBSimulatorControl/FBSimulatorHID.h>
#import <FBSimulatorControl/FBSimulatorHIDEvent.h>
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>
#import <FBSimulatorControl/FBSimulatorKeychainCommands.h>
#import <FBSimulatorControl/FBSimulatorLaunchCtlCommands.h>
#import <FBSimulatorControl/FBSimulatorLifecycleCommands.h>
#import <FBSimulatorControl/FBSimulatorMediaCommands.h>
#import <FBSimulatorControl/FBSimulatorSettingsCommands.h>
#import <FBSimulatorControl/FBSimulatorVideoStream.h>

#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
