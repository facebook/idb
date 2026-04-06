/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Headers with C type definitions must come before any header that imports
// FBSimulatorControl-Swift.h, because the generated Swift header may reference
// these types (e.g. FBSimulatorBootOptions).
#import <FBSimulatorControl/FBAppleSimctlCommandExecutor.h>
#import <FBSimulatorControl/FBCoreSimulatorNotifier.h>
#import <FBSimulatorControl/FBDefaultsModificationStrategy.h>
#import <FBSimulatorControl/FBFramebuffer.h>
#import <FBSimulatorControl/FBSimDeviceWrapper.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorAccessibilityCommands.h>
#import <FBSimulatorControl/FBSimulatorApplicationCommands.h>
#import <FBSimulatorControl/FBSimulatorBootConfiguration.h>
#import <FBSimulatorControl/FBSimulatorBootStrategy.h>
#import <FBSimulatorControl/FBSimulatorBootVerificationStrategy.h>
#import <FBSimulatorControl/FBSimulatorBridge.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorConfiguration+CoreSimulator.h>
#import <FBSimulatorControl/FBSimulatorControl+PrincipalClass.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControlFrameworkLoader.h>
#import <FBSimulatorControl/FBSimulatorCrashLogCommands.h>
#import <FBSimulatorControl/FBSimulatorDapServerCommands.h>
#import <FBSimulatorControl/FBSimulatorDebuggerCommands.h>
#import <FBSimulatorControl/FBSimulatorError.h>
#import <FBSimulatorControl/FBSimulatorFileCommands.h>
#import <FBSimulatorControl/FBSimulatorHID.h>
#import <FBSimulatorControl/FBSimulatorHIDEvent.h>
#import <FBSimulatorControl/FBSimulatorImage.h>
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>
#import <FBSimulatorControl/FBSimulatorKeychainCommands.h>
#import <FBSimulatorControl/FBSimulatorLaunchCtlCommands.h>
#import <FBSimulatorControl/FBSimulatorLaunchedApplication.h>
#import <FBSimulatorControl/FBSimulatorLifecycleCommands.h>
#import <FBSimulatorControl/FBSimulatorLocationCommands.h>
#import <FBSimulatorControl/FBSimulatorLogCommands.h>
#import <FBSimulatorControl/FBSimulatorMediaCommands.h>
#import <FBSimulatorControl/FBSimulatorMemoryCommands.h>
#import <FBSimulatorControl/FBSimulatorNotificationCommands.h>
#import <FBSimulatorControl/FBSimulatorNotificationUpdateStrategy.h>
#import <FBSimulatorControl/FBSimulatorProcessSpawnCommands.h>
#import <FBSimulatorControl/FBSimulatorScreenshotCommands.h>
#import <FBSimulatorControl/FBSimulatorServiceContext.h>
#import <FBSimulatorControl/FBSimulatorSet.h>
#import <FBSimulatorControl/FBSimulatorSettingsCommands.h>
#import <FBSimulatorControl/FBSimulatorVideo.h>
#import <FBSimulatorControl/FBSimulatorVideoRecordingCommands.h>
#import <FBSimulatorControl/FBSimulatorVideoStream.h>
#import <FBSimulatorControl/FBSimulatorXCTestCommands.h>
#import <FBSimulatorControl/FBSurfaceImageGenerator.h>

#if __has_include(<FBSimulatorControl/FBSimulatorControl-Swift.h>)
 #import <FBSimulatorControl/FBSimulatorControl-Swift.h>
#endif
