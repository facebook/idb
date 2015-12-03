/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;
@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorBinary;
@class FBSimulatorSession;
@class FBSimulatorSessionState;
@class FBSimulatorSessionStateGenerator;
@protocol FBTerminationHandle;

/**
 Notification that is fired when a Session starts Successfully.
 */
extern NSString *const FBSimulatorSessionDidStartNotification;

/**
 Notification that is fired when a Session ends.
 */
extern NSString *const FBSimulatorSessionDidEndNotification;

/**
 Notification that is fired when a Application Process Launches.
 */
extern NSString *const FBSimulatorSessionApplicationProcessDidLaunchNotification;

/**
 Notification that is fired when a Application Process Terminatees.
 */
extern NSString *const FBSimulatorSessionApplicationProcessDidTerminateNotification;

/**
 Notification that is fired when a Agent Process Launches.
 */
extern NSString *const FBSimulatorSessionAgentProcessDidLaunchNotification;

/**
 Notification that is fired when a Agent Process Terminate.
 */
extern NSString *const FBSimulatorSessionAgentProcessDidTerminateNotification;

/**
 UserInfo key for Session State.
 */
extern NSString *const FBSimulatorSessionStateKey;

/**
 UserInfo key for Subject of the Notfication.
 */
extern NSString *const FBSimulatorSessionSubjectKey;

/**
 UserInfo key for Determining whether the lifecycle event was expected (initiated) or not (a crash).
 */
extern NSString *const FBSimulatorSessionExpectedKey;

/**
 A Class responsible for managing the running state of a Simulator Session.
 Has notiions of the running applications, agents and simulator itself.
 Fires notifications when this knowledge changes.
 Must be strongly referenced, or else notifications will not fire.
 */
@interface FBSimulatorSessionLifecycle : NSObject

#pragma mark - Initializers

/**
 The Designated Initializer for creating a session Lifecyle.

 @param session the Session to notify the lifcycle for
 @returns a new FBSimulatorSessionLifecycle object.
 */
+ (instancetype)lifecycleWithSession:(FBSimulatorSession *)session;

#pragma mark - Lifecyle

/**
 Called when the session is started. Must only be called once per lifecycle, and the first call of the lifecycle.
 */
- (void)didStartSession;

/**
 Called when the session is finished. Must only be called once per lifecycle, and the last call of the lifecycle.
 */
- (void)didEndSession;

/**
 Called just before the Simulator starts.
 */
- (void)simulatorWillStart:(FBSimulator *)simulator;

/**
 Called when the Simulator starts.
 */
- (void)simulator:(FBSimulator *)simulator didStartWithProcessIdentifier:(pid_t)processIdentifier terminationHandle:(id<FBTerminationHandle>)terminationHandle;

/**
 Called just before the Simulator is manually terminated.
 */
- (void)simulatorWillTerminate:(FBSimulator *)simulator;

/**
 Called when an agent has starts.
 */
- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStartWithProcessIdentifier:(pid_t)processIdentifier stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr;

/**
 Called just before the agent is manually terminated.
 */
- (void)agentWillTerminate:(FBSimulatorBinary *)agentBinary;

/**
 Called when an Application starts.
 */
- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStartWithProcessIdentifier:(pid_t)processIdentifier stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr;

/**
 Called just before an Application is manually terminated.
 */
- (void)applicationWillTerminate:(FBSimulatorApplication *)application;

/**
 Called there's new Diagnostic information for the Session.
 */
- (void)sessionDidGainDiagnosticInformationWithName:(NSString *)diagnosticName data:(id)data;

/**
 Called there's new Diagnostic information for an Application.
 */
- (void)application:(FBSimulatorApplication *)application didGainDiagnosticInformationWithName:(NSString *)diagnosticName data:(id)data;

/**
 Associates a Termination Handle to be called when the session has completed
 */
- (void)associateEndOfSessionCleanup:(id<FBTerminationHandle>)terminationHandle;

/**
 The Session State.
 */
@property (nonatomic, strong, readonly) FBSimulatorSessionState *currentState;

#pragma mark - Persistence

/**
 Returns a Path for storing information to a file associated with a Session.
 Can be used to store large amounts of data for aggregation later.
 
 @param key a key to uniquely identify the file for this Session. If nil, files are guaranteed to be unique for the Session.
 @param extension the file extension of the returned file.
 */
- (NSString *)pathForStorage:(NSString *)key ofExtension:(NSString *)extension;

@end
