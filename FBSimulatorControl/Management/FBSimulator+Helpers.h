/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBApplicationDescriptor;
@class FBSimulatorLaunchCtl;

NS_ASSUME_NONNULL_BEGIN

static NSString *const ApplicationTypeKey = @"ApplicationType";
static NSString *const ApplicationPathKey = @"Path";

/**
 Helper Methods & Properties for FBSimulator.
 */
@interface FBSimulator (Helpers)

#pragma mark Properties

/**
 Creates a FBSimulatorLaunchCtl for the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorLaunchCtl *launchctl;

/**
 The DeviceSetPath of the Simulator.
 */
@property (nonatomic, nullable, copy, readonly) NSString *deviceSetPath;

/*
 Fetches an NSArray<FBProcessInfo *> of the subprocesses of the launchd_sim.
 */
@property (nonatomic, copy, readonly) NSArray<FBProcessInfo *> *launchdSimSubprocesses;

#pragma mark Methods

/**
 Convenience method for obtaining SimulatorState from a String.

 @param stateString the State String to convert from
 @return an Enumerated State for the String.
 */
+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString;

/**
 Convenience method for obtaining a description of Simulator State

 @param state the Enumerated State to convert from.
 @return a String Representation of the Simulator State.
 */
+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state;

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @returns YES if the Simulator transitioned to the given state with the default timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state;

/**
 Synchronously waits on the provided state.

 @param state the state to wait on
 @param timeout timeout
 @returns YES if the Simulator transitioned to the given state with the timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout;

/**
 A Synchronous wait, with a default timeout, producing a meaningful error message.

 @param state the state to wait on
 @param error an error out for a timeout error if one occurred
 @returns YES if the Simulator transitioned to the given state with the timeout, NO otherwise
 */
- (BOOL)waitOnState:(FBSimulatorState)state withError:(NSError **)error;

/**
 Calls `freeSimulator:error:` on this device's pool, with the reciever as the first argument.

 @param error an error out for any error that occured.
 @returns YES if the freeing of the device was successful, NO otherwise.
 */
- (BOOL)freeFromPoolWithError:(NSError **)error;

/**
 Erases the Simulator, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)eraseWithError:(NSError **)error;

/**
 Brings the Simulator window to front, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)focusWithError:(NSError **)error;

/**
 A Dictionary Representing the iPhone Simulator.app Preferences.
 */
+ (NSDictionary<NSString *, id> *)simulatorApplicationPreferences;

@end

NS_ASSUME_NONNULL_END
