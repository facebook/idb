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
@class FBSimulatorApplication;
@class FBSimulatorInteraction;
@class FBSimulatorLaunchCtl;

@interface FBSimulator (Helpers)

/**
 Creates an `FBSimulatorInteraction` for the reciever.
 */
- (FBSimulatorInteraction *)interact;

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
 Erases the Simulator, with a descriptive message in the event of a failure.

 @param error a descriptive error for any error that occurred.
 @return YES if successful, NO otherwise.
 */
- (BOOL)eraseWithError:(NSError **)error;

/**
 Fetches the FBSimulatorApplication instance by Bundle ID, on the Simulator.

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return a FBSimulatorApplication instance if one could be obtained, NO otherwise.
 */
- (FBSimulatorApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Determinates whether a provided Bundle ID represents a System Application

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return YES if the Application with the provided is a System Application, NO otherwise.
*/
- (BOOL)isSystemApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/**
 Returns the Process Info for a Application by Bundle ID.

 @param bundleID the Bundle ID to fetch an installed application for.
 @param error an error out for any error that occurs.
 @return An FBProcessInfo for the Application if one is running, nil otherwise.
 */
- (FBProcessInfo *)runningApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error;

/*
 Fetches an NSArray<FBProcessInfo *> of the subprocesses of the launchd_sim.
 */
- (NSArray *)launchdSimSubprocesses;

/**
 Creates a FBSimDeviceWrapper for the Simulator.
 */
- (FBSimDeviceWrapper *)simDeviceWrapper;

/**
 Creates a FBSimulatorLaunchCtl for the Simulator.
 */
- (FBSimulatorLaunchCtl *)launchctl;

/*
 A Set of process names that are used to determine whether all the Simulator OS services
 have been launched after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return a NSSet<NSString> of the required process names.
 */
- (NSSet *)requiredProcessNamesToVerifyBooted;

/**
 Returns the home folder of the last application launched
 */
- (NSString *)homeDirectoryOfLastLaunchedApplication;

@end
