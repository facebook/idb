/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBDebugDescribeable.h>
#import <FBSimulatorControl/FBJSONConversion.h>

@protocol FBSimulatorEventSink;
@protocol FBSimulatorLogger;
@class FBProcessInfo;
@class FBProcessQuery;
@class FBSimulatorBridge;
@class FBSimulatorConfiguration;
@class FBSimulatorDiagnostics;
@class FBSimulatorHistory;
@class FBSimulatorLogger;
@class FBSimulatorPool;
@class FBSimulatorSet;
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
 Uses the known values of SimDeviceType ProductFamilyID, to construct an enumeration.
 These mirror the values from -[SimDeviceState productFamilyID].
 */
typedef NS_ENUM(NSInteger, FBSimulatorProductFamily) {
  FBSimulatorProductFamilyUnknown = 0,
  FBSimulatorProductFamilyiPhone = 1,
  FBSimulatorProductFamilyiPad = 2,
  FBSimulatorProductFamilyAppleTV = 3,
  FBSimulatorProductFamilyAppleWatch = 4,
};

/**
 Defines the High-Level Properties and Methods that exist on any Simulator returned from `FBSimulatorPool`.
 */
@interface FBSimulator : NSObject <FBJSONSerializationDescribeable, FBDebugDescribeable>

/**
 The Underlying SimDevice.
 */
@property (nonatomic, strong, readonly) SimDevice *device;

/**
 Whether the Simulator is allocated or not.
 */
@property (nonatomic, assign, readonly, getter=isAllocated) BOOL allocated;

/**
 The Simulator Set that the Simulator belongs to.
 */
@property (nonatomic, weak, readonly) FBSimulatorSet *set;

/**
 The Pool to which the Simulator belongs, if Any.
 */
@property (nonatomic, weak, readonly) FBSimulatorPool *pool;

/**
 Where the events for the Simulator should be sent.
 */
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

/**
 An Event Sink that can be updated to the user's choosing.
 Will be called when sending events to `eventSink`.
 Events should be sent to `eventSink` and not this property; events will propogate here automatically.
 */
@property (nonatomic, strong, readwrite) id<FBSimulatorEventSink> userEventSink;

/**
 The Simulator's Logger.
 */
@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;

/**
 History of the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorHistory *history;

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
 The Product Family of the Simulator.
 */
@property (nonatomic, assign, readonly) FBSimulatorProductFamily productFamily;

/**
 A string representation of the Simulator State.
 */
@property (nonatomic, copy, readonly) NSString *stateString;

/**
 The Directory that Contains the Simulator's Data
 */
@property (nonatomic, copy, readonly) NSString *dataDirectory;

/**
 The Directory that FBSimulatorControl uses to store auxillary files.
 */
@property (nonatomic, copy, readonly) NSString *auxillaryDirectory;

/**
 The FBSimulatorConfiguration representing this Simulator.
 */
@property (nonatomic, copy, readonly) FBSimulatorConfiguration *configuration;

/**
 The launchd_sim process info for the Simulator, if launched.
 */
@property (nonatomic, copy, readonly) FBProcessInfo *launchdSimProcess;

/**
 The FBProcessInfo associated with the Container Application that launched the Simulator.
 */
@property (nonatomic, copy, readonly) FBProcessInfo *containerApplication;

/**
 The Bridge of the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorBridge *bridge;

/**
 The FBSimulatorDiagnostics instance for fetching diagnostics for the Simulator.
 */
@property (nonatomic, strong, readonly) FBSimulatorDiagnostics *diagnostics;

@end
