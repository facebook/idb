/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessLaunchConfiguration;
@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorBinary;
@class FBSimulatorSession;

typedef NS_ENUM(NSInteger, FBSimulatorSessionLifecycleState) {
  FBSimulatorSessionLifecycleStateNotStarted,
  FBSimulatorSessionLifecycleStateStarted,
  FBSimulatorSessionLifecycleStateEnded
};

/**
 An Object representing the current state of a running process.
 Implements equality to uniquely identify a launched process.
 */
@interface FBSimulatorSessionProcessState : NSObject<NSCopying>

/**
 The Process Identifier for the running process
 */
@property (nonatomic, assign, readonly) NSInteger processIdentifier;

/**
 The Date the Process was launched
 */
@property (nonatomic, copy, readonly) NSDate *launchDate;

/**
 The Launch Config of the Launched Process
 */
@property (nonatomic, copy, readonly) FBProcessLaunchConfiguration *launchConfiguration;

/**
 A key-value store of arbitrary diagnostic information for the process
 */
@property (nonatomic, copy, readonly) NSDictionary *diagnostics;

@end

/**
 An Object representing the current state of the Simulator Session.
 */
@interface FBSimulatorSessionState : NSObject<NSCopying>

/**
 The Session that is producing this information.
 */
@property (nonatomic, weak, readonly) FBSimulatorSession *session;

/**
 The Simulator for the Session.
 */
@property (nonatomic, weak, readonly) FBSimulator *simulator;

/**
 The Position in the lifecycle of the session state.
 */
@property (nonatomic, assign, readonly) FBSimulatorSessionLifecycleState lifecycle;

/**
 The Running processes on the Simulator.
 Ordering is determined by time of launch; the most recently launched process is first.
 */
@property (nonatomic, copy, readonly) NSArray *runningProcesses;

/**
 The last state, may be nil.
 */
@property (nonatomic, copy, readonly) FBSimulatorSessionState *previousState;

@end
