/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@class FBSimDeviceWrapper;
@class FBSimulatorInteraction;

@interface FBSimulator (Helpers)

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
 Convenience method for obtaining a description of Simulator State
 */
+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state;

/**
 Convenience method for obtaining SimulatorState from a String.
 */
+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString;

/**
 Calls `freeSimulator:error:` on this device's pool, with the reciever as the first argument.

 @param error an error out for any error that occured.
 @returns YES if the freeing of the device was successful, NO otherwise.
 */
- (BOOL)freeFromPoolWithError:(NSError **)error;

/**
 Returns a location that can be used to store ephemeral information about a Simulator.
 Can be used to store large amounts of data for aggregation later.

 @param key a key to uniquely identify the file for this Session. If nil, files are guaranteed to be unique for the Session.
 @param extension the file extension of the returned file.
 */
- (NSString *)pathForStorage:(NSString *)key ofExtension:(NSString *)extension;

/**
 Erases the Simulator, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)eraseWithError:(NSError **)error;

/**
 Creates an `FBSimulatorInteraction` for the reciever.
 */
- (FBSimulatorInteraction *)interact;

/**
 Creates a FBSimDeviceWrapper for the Simulator.
 */
- (FBSimDeviceWrapper *)simDeviceWrapper;

/*
 A Set of process names that are used to determine whether all the Simulator OS services
 have been launched after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return a NSSet<NSString> of the required process names.
 */
- (NSSet *)requiredProcessNamesToVerifyBooted;

@end
