/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBSimulatorControl/FBSimulatorAgentCommands.h>
#import <FBSimulatorControl/FBSimulatorApplicationCommands.h>
#import <FBSimulatorControl/FBSimulatorApplicationDataCommands.h>
#import <FBSimulatorControl/FBSimulatorBridgeCommands.h>
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
@class FBSimulatorPool;
@class FBSimulatorSet;
@class SimDevice;

/**
 Defines the High-Level Properties and Methods that exist on any Simulator returned from `FBSimulatorPool`.
 */
@interface FBSimulator : NSObject <FBiOSTarget, FBCrashLogCommands, FBScreenshotCommands, FBSimulatorAgentCommands, FBSimulatorApplicationCommands, FBApplicationDataCommands, FBSimulatorBridgeCommands, FBSimulatorKeychainCommands, FBSimulatorSettingsCommands, FBSimulatorXCTestCommands, FBSimulatorLifecycleCommands, FBSimulatorLaunchCtlCommands, FBSimulatorMediaCommands>

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
 The Pool to which the Simulator belongs, if Any.
 */
@property (nonatomic, weak, readonly, nullable) FBSimulatorPool *pool;

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

/*
 A command executor for simctl
 */
@property (nonatomic, strong, readonly) FBAppleSimctlCommandExecutor *simctlExecutor;

@end

NS_ASSUME_NONNULL_END
