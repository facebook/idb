/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorHistory;
@class FBSimulatorInteraction;
@class FBSimulatorSessionLogs;

typedef NS_ENUM(NSInteger, FBSimulatorSessionState) {
  FBSimulatorSessionStateNotStarted,
  FBSimulatorSessionStateStarted,
  FBSimulatorSessionStateEnded
};

/**
 Notification that is fired when a Session starts Successfully.
 */
extern NSString *const FBSimulatorSessionDidStartNotification;

/**
 Notification that is fired when a Session ends.
 */
extern NSString *const FBSimulatorSessionDidEndNotification;

/**
 Represents the lifecycle of a connection to a Simulator.
 A Session is inert, until `start` is called.
 */
@interface FBSimulatorSession : NSObject

/**
 Creates a new `FBSimulatorSession` with the provided parameters. Will not launch a session until `start:` is called.

 @param simulator the Simulator to manage the session for.
 @returns a new `FBSimulatorSession`.
 */
+ (instancetype)sessionWithSimulator:(FBSimulator *)simulator;

/**
 The Simulator for this session
 */
@property (nonatomic, strong, readonly) FBSimulator *simulator;

/**
 Returns the Session Information for the reciever.
 */
@property (nonatomic, strong, readonly) FBSimulatorHistory *history;

/**
 Returns the Logs associated with this Session.
 */
@property (nonatomic, strong, readonly) FBSimulatorSessionLogs *logs;

/**
 Returns the state of the Session.
 */
@property (nonatomic, assign, readonly) FBSimulatorSessionState state;

/**
 Returns an Interaction for Interacting with the Sessions.
 */
- (FBSimulatorInteraction *)interact;

/**
 Terminates the Session, freeing any allocated resources.
 */
- (BOOL)terminateWithError:(NSError **)error;


@end
