/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorAccessibilityCommands.h>
#import <FBSimulatorControl/FBSimulatorAgentCommands.h>
#import <FBSimulatorControl/FBSimulatorApplicationCommands.h>
#import <FBSimulatorControl/FBSimulatorFileCommands.h>
#import <FBSimulatorControl/FBSimulatorKeychainCommands.h>
#import <FBSimulatorControl/FBSimulatorLaunchCtlCommands.h>
#import <FBSimulatorControl/FBSimulatorLifecycleCommands.h>
#import <FBSimulatorControl/FBSimulatorMediaCommands.h>
#import <FBSimulatorControl/FBSimulatorSettingsCommands.h>
#import <FBSimulatorControl/FBSimulatorVideoRecordingCommands.h>
#import <FBSimulatorControl/FBSimulatorXCTestCommands.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBSimulatorEventSink;
@protocol FBControlCoreLogger;

@class FBAppleSimctlCommandExecutor;
@class FBControlCoreLogger;
@class FBProcessFetcher;
@class FBProcessInfo;
@class FBSimulatorConfiguration;
@class FBSimulatorDiagnostics;
@class FBSimulatorSet;
@class SimDevice;

/**
 An implementation of FBiOSTarget for iOS Simulators.
 */
@interface FBSimulator : NSObject <FBiOSTarget, FBCrashLogCommands, FBLocationCommands, FBScreenshotCommands, FBAccessibilityCommands, FBSimulatorAgentCommands, FBSimulatorApplicationCommands, FBFileCommands, FBSimulatorKeychainCommands, FBSimulatorSettingsCommands, FBSimulatorLifecycleCommands, FBSimulatorLaunchCtlCommands, FBSimulatorMediaCommands>

#pragma mark Properties

/**
 The Underlying SimDevice.
 */
@property (nonatomic, strong, readonly, nonnull) SimDevice *device;

/**
 Whether the Simulator is allocated or not.
 */
@property (nonatomic, assign, readonly, getter=isAllocated) BOOL allocated;

/**
 The Simulator Set that the Simulator belongs to.
 */
@property (nonatomic, weak, readonly, nullable) FBSimulatorSet *set;

/**
 Where the events for the Simulator should be sent.
 */
@property (nonatomic, strong, readonly, nullable) id<FBSimulatorEventSink> eventSink;

/**
 An Event Sink that can be updated to the user's choosing.
 Will be called when sending events to `eventSink`.
 Events should be sent to `eventSink` and not this property; events will propogate here automatically.
 */
@property (nonatomic, strong, readwrite, nullable) id<FBSimulatorEventSink> userEventSink;

/**
 The State of the allocated Simulator.
 */
@property (nonatomic, assign, readonly) FBiOSTargetState state;

/**
 The Product Family of the Simulator.
 */
@property (nonatomic, assign, readonly) FBControlCoreProductFamily productFamily;

/**
 A string representation of the Simulator State.
 */
@property (nonatomic, copy, readonly, nonnull) FBiOSTargetStateString stateString;

/**
 The Directory that Contains the Simulator's Data
 */
@property (nonatomic, copy, readonly, nullable) NSString *dataDirectory;

/**
 The FBSimulatorConfiguration representing this Simulator.
 */
@property (nonatomic, copy, readonly, nullable) FBSimulatorConfiguration *configuration;

/**
 The FBProcessInfo associated with the Container Application that launched the Simulator.
 */
@property (nonatomic, copy, readonly, nullable) FBProcessInfo *containerApplication;

/**
 The FBSimulatorDiagnostics instance for fetching diagnostics for the Simulator.
 */
@property (nonatomic, strong, readonly, nonnull) FBSimulatorDiagnostics *simulatorDiagnostics;

/**
 A command executor for simctl
 */
@property (nonatomic, strong, readonly) FBAppleSimctlCommandExecutor *simctlExecutor;

/**
 The directory path of the expected location of the CoreSimulator logs directory.
 */
@property (nonatomic, copy, readonly) NSString *coreSimulatorLogsDirectory;

@end

NS_ASSUME_NONNULL_END
