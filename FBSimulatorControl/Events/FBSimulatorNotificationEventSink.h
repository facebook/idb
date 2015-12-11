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

/**
 Notification that is fired when a Simulator Process Starts.
 */
extern NSString *const FBSimulatorDidLaunchNotification;

/**
 Notification that is fired when a Simulator Process Terminates.
 */
extern NSString *const FBSimulatorDidTerminateNotification;

/**
 Notification that is fired when a Application Process Launches.
 */
extern NSString *const FBSimulatorApplicationProcessDidLaunchNotification;

/**
 Notification that is fired when a Application Process Terminatees.
 */
extern NSString *const FBSimulatorApplicationProcessDidTerminateNotification;

/**
 Notification that is fired when a Agent Process Launches.
 */
extern NSString *const FBSimulatorAgentProcessDidLaunchNotification;

/**
 Notification that is fired when a Agent Process Terminate.
 */
extern NSString *const FBSimulatorAgentProcessDidTerminateNotification;

/**
 Notification that is fired when diagnostic information is gained.
 */
extern NSString *const FBSimulatorGainedDiagnosticInformation;

/**
 Notification the Simulator State changed.
 */
extern NSString *const FBSimulatorStateDidChange;

/**
 Notification UserInfo for whether the termination was expected or not.
 */
extern NSString *const FBSimulatorExpectedTerminationKey;

/**
 Notification UserInfo for the process in question.
 */
extern NSString *const FBSimulatorProcessKey;

/**
 Notification UserInfo for the name of a diagnostic.
 */
extern NSString *const FBSimulatorDiagnosticName;

/**
 Notification UserInfo for value of a diagnostic.
 */
extern NSString *const FBSimulatorDiagnosticValue;

/**
 Notification UserInfo for Simulator State.
 */
extern NSString *const FBSimulatorStateKey;

/**
 An Event Sink that will fire NSNotifications.
 */
@interface FBSimulatorNotificationEventSink : NSObject <FBSimulatorEventSink>

+ (instancetype)withSimulator:(FBSimulator *)simulator;

@end
