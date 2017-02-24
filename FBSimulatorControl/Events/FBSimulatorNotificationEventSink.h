/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
 Notification that is fired when Test Manager Connects.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameTestManagerDidConnect;

/**
 Notification that is fired when Test Manager Disconnects.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameTestManagerDidDisconnect;

/**
 Notification that is fired when diagnostic information is gained.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameGainedDiagnosticInformation;

/**
 Notification the Simulator State changed.
 */
extern FBSimulatorNotificationName const FBSimulatorNotificationNameStateDidChange;

/**
 Notification UserInfo for whether the termination was expected or not.
 */
extern NSString *const FBSimulatorExpectedTerminationKey;

/**
 Notification UserInfo for the process in question.
 */
extern NSString *const FBSimulatorProcessKey;

/**
 Notification UserInfo for the Simulator Bridge.
 */
extern NSString *const FBSimulatorConnectionKey;

/**
 Notification UserInfo for the name of a diagnostic.
 */
extern NSString *const FBSimulatorDiagnosticLog;

/**
 Notification UserInfo for Simulator State.
 */
extern NSString *const FBSimulatorStateKey;

/**
 Notification UserInfo for Test Manager.
 */
extern NSString *const FBSimulatorTestManagerKey;

/**
 An Event Sink that will fire NSNotifications.
 */
@interface FBSimulatorNotificationNameEventSink : NSObject <FBSimulatorEventSink>

+ (instancetype)withSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
