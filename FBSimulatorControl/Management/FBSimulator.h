/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessQuery;
@class FBSimulatorApplication;
@class FBSimulatorConfiguration;
@class FBSimulatorLaunchInfo;
@class FBSimulatorLogs;
@class FBSimulatorPool;
@class FBSimulatorSession;
@class SimDevice;

/**
 The Default timeout for waits.
 */
extern NSTimeInterval const FBSimulatorDefaultTimeout;

/**
 Notification that is fired when a Simulator Process Starts.
 */
extern NSString *const FBSimulatorDidLaunchNotification;

/**
 Notification that is fired when a Simulator Process Terminates.
 */
extern NSString *const FBSimulatorDidTerminateNotification;

/**
 Uses the known values of SimDevice State, to construct an enumeration.
 These mirror the values from -[SimDeviceState state].
 */
typedef NS_ENUM(NSInteger, FBSimulatorState) {
  FBSimulatorStateCreating = 0,
  FBSimulatorStateShutdown = 1,
  FBSimulatorStateBooting = 2,
  FBSimulatorStateBooted = 3,
  FBSimulatorStateShuttingDown = 4,
  FBSimulatorStateUnknown = -1,
};

/**
 Defines the High-Level Properties and Methods that exist on any Simulator returned from `FBSimulatorPool`.
 */
@interface FBSimulator : NSObject

/**
 The Underlying SimDevice.
 */
@property (nonatomic, strong, readonly) SimDevice *device;

/**
 Whether the Simulator is allocated or not.
 */
@property (nonatomic, assign, readonly, getter=isAllocated) BOOL allocated;

/**
 The Pool to which the Simulator belongs.
 */
@property (nonatomic, weak, readonly) FBSimulatorPool *pool;

/**
 The Session to which the Simulator belongs, if any.
 */
@property (nonatomic, weak, readonly) FBSimulatorSession *session;

/**
 The Name of the allocated Simulator.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The UDID of the allocated Simulator.
 */
@property (nonatomic, copy, readonly) NSString *udid;

/**
 The State of the allocated Simulator.
 */
@property (nonatomic, assign, readonly) FBSimulatorState state;

/**
 A string representation of the Simulator State.
 */
@property (nonatomic, copy, readonly) NSString *stateString;

/**
 The Directory that Contains the Simulator's Data
 */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/**
 The Application that the Simulator should be launched with.
 */
@property (nonatomic, copy, readonly) FBSimulatorApplication *simulatorApplication;

/**
 The FBSimulatorConfiguration representing this Simulator.
 */
@property (nonatomic, copy, readonly) FBSimulatorConfiguration *configuration;

/**
 The FBSimulatorLaunchInfo object for the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorLaunchInfo *launchInfo;

/**
 The FBSimulatorLogs instance for fetching logs for the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorLogs *logs;

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

@end
