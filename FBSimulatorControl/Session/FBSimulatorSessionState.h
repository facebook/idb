/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulator.h>

@class FBProcessLaunchConfiguration;
@class FBSimulatorApplication;
@class FBSimulatorBinary;
@class FBSimulatorSession;

typedef NS_ENUM(NSInteger, FBSimulatorSessionLifecycleState) {
  FBSimulatorSessionLifecycleStateNotStarted,
  FBSimulatorSessionLifecycleStateStarted,
  FBSimulatorSessionLifecycleStateEnded
};

/**
 An Immutable value representing the current state of the Simulator Session.
 Can be used to interrogate the changes to the operation of the Simulator over time.
 */
@interface FBSimulatorSessionState : NSObject<NSCopying>

/**
 The Session that is producing this information. The Session is a reference, so represents the current state of the world.
This does not behave like a value within the Session State, so it's contents may change over time.
 */
@property (nonatomic, weak, readonly) FBSimulatorSession *session;

/**
 The Simulator for the Session. The Simulator is a reference, so represents the current state of the world.
 This does not behave like a value within the Session State, so it's contents may change over time.
 */
@property (nonatomic, weak, readonly) FBSimulator *simulator;

/**
 The Timestamp for the creation of the reciever.
 */
@property (nonatomic, copy, readonly) NSDate *timestamp;

/**
 The Enumerated state of the Simulator.
 */
@property (nonatomic, assign, readonly) FBSimulatorState simulatorState;

/**
 The Position in the lifecycle of the session state.
 */
@property (nonatomic, assign, readonly) FBSimulatorSessionLifecycleState lifecycle;

/**
 The Running processes on the Simulator.
 Ordering is determined by time of launch; the most recently launched process is first.
 Is an NSArray<FBUserLaunchedProcess>
 */
@property (nonatomic, copy, readonly) NSArray *runningProcesses;

/**
 Per-Session Diagnostic Information.
 */
@property (nonatomic, copy, readonly) NSDictionary *diagnostics;

/**
 The last state, may be nil if this is the first instance.
 */
@property (nonatomic, copy, readonly) FBSimulatorSessionState *previousState;

/**
 A String description of FBSimulatorSessionLifecycleState
 */
+ (NSString *)stringForLifecycleState:(FBSimulatorSessionLifecycleState)lifecycleState;

/**
 A String description of the difference between the provided states.
 */
+ (NSString *)describeDifferenceBetween:(FBSimulatorSessionState *)first and:(FBSimulatorSessionState *)second;

/**
 Describes all the changes of the reciever, to the first change.
 */
- (NSString *)recursiveChangeDescription;

@end
