/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBSimulatorEventSink;
@class FBProcessQuery;
@class FBSimulatorApplication;
@class FBSimulatorConfiguration;
@class FBSimulatorHistory;
@class FBSimulatorLaunchInfo;
@class FBSimulatorLogs;
@class FBSimulatorPool;
@class FBSimulatorSession;
@class SimDevice;

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
 Where the events for the Simulator should be sent.
 */
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

/**
 History of the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorHistory *history;

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

@end
