/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorEventSink.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Notification Enumeration.
 */
typedef NSString *FBSimulatorNotificationName NS_STRING_ENUM;

/**
 Notification that is fired when a Simulator Launches.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameDidLaunch;

/**
 Notification that is fired when a Simulator Launches.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameDidTerminate;

/**
 Notification that is fired when a Simulator's Container Process Starts.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameSimulatorApplicationDidLaunch;

/**
 Notification that is fired when a Simulator's Container Process Starts.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameSimulatorApplicationDidTerminate;

/**
 Notification that is fired when a Simulator Framebuffer Starts.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameConnectionDidConnect;

/**
 Notification that is fired when a Simulator Framebuffer Terminates.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameConnectionDidDisconnect;

/**
 Notification that is fired when a Application Process Launches.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameApplicationProcessDidLaunch;

/**
 Notification that is fired when a Application Process Terminatees.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameApplicationProcessDidTerminate;

/**
 Notification that is fired when a Agent Process Launches.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameAgentProcessDidLaunch;

/**
 Notification that is fired when a Agent Process Terminate.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameAgentProcessDidTerminate;

/**
 Notification the Simulator State changed.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameStateDidChange;

/**
 Notification UserInfo Enumeration.
 */
typedef NSString *FBSimulatorNotificationUserInfoKey NS_STRING_ENUM;

/**
 Notification UserInfo for whether the termination was expected or not.
 */
extern FBSimulatorNotificationUserInfoKey const FBSimulatorNotificationUserInfoKeyExpectedTermination;

/**
 Notification UserInfo for the process in question.
 */
extern FBSimulatorNotificationUserInfoKey const FBSimulatorNotificationUserInfoKeyProcess;

/**
 Notification UserInfo for the Simulator Bridge.
 */
extern FBSimulatorNotificationUserInfoKey const FBSimulatorNotificationUserInfoKeyConnection;

/**
 Notification UserInfo for Simulator State.
 */
extern FBSimulatorNotificationUserInfoKey const FBSimulatorNotificationUserInfoKeyState;

/**
 Notification UserInfo for Test Manager.
 */
extern FBSimulatorNotificationUserInfoKey const FBSimulatorNotificationUserInfoKeyTestManager;

/**
 An Event Sink that will fire NSNotifications.
 */
@interface FBSimulatorNotificationNameEventSink : NSObject <FBSimulatorEventSink>

+ (instancetype)withSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
