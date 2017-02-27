/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import "FBSimulatorControlTestCase.h"

@class FBSimulator;
@class FBSimulatorControl;
@class FBSimulatorPool;

NS_ASSUME_NONNULL_BEGIN

/**
 FBSimulatorControl Assertion Helpers.
 */
@interface XCTestCase (FBSimulatorControlAssertions)

#pragma mark Sessions

/**
 Assertion failure if the Session fails to terminate
 */
- (void)assertShutdownSimulatorAndTerminateSession:(FBSimulator *)simulator;

#pragma mark Strings

/**
 Assertion failure if the needle can't be found in the haystack.
 */
- (void)assertNeedle:(NSString *)needle inHaystack:(NSString *)haystack;

#pragma mark Simulators

/**
 Assertion failure if the Simulator isn't booted.
 */
- (void)assertSimulatorBooted:(FBSimulator *)simulator;

/**
 Assertion failure if the Simulator isn't shutdown.
 */
- (void)assertSimulatorShutdown:(FBSimulator *)simulator;

#pragma mark Processes

/**
 Assertion failure if there isn't a last launched application or launchctl isn't aware of the process.
 */
- (void)assertLastLaunchedApplicationIsRunning:(FBSimulator *)simulator;

@end

/**
 Assertion helpers for FBSimulatorControlTestCase.
 */
@interface FBSimulatorControlTestCase (FBSimulatorControlAssertions)

/**
 Asserts that a Simulator with the default configuration can be obtained

 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsSimulator;

/**
 Asserts that a Simulator with the provided configuration can be obtained

 @param configuration the configiuration of the Simulator to obtain.
 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration;

/**
 Asserts that a booted Simulator with the default configuration can be obtained.

 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsBootedSimulator;

/**
 Asserts that a booted Simulator with the default configuration can be obtained.

 @param application the Application to install.
 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsBootedSimulatorWithInstalledApplication:(FBApplicationDescriptor *)application;

/**
 Asserts that a booted Simulator with the provided configurations can be obtained.

 @param configuration the Simulator Configuration to obtain.
 @param launchConfiguration the Launch configuration to boot with.
 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsBootedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration launchConfiguration:(FBSimulatorBootConfiguration *)launchConfiguration;

/**
 An Assertion for:
 - Installing the Application (if relevant).
 - Launching the Application with the given configuration.

 @param simulator the booted Simulator.
 @param application the Application to install.
 @param applicationLaunchConfiguration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator launchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration;

/**
 An Assertion for:
 - Obtaining a Simulator with a given configuration.
 - Launching it with the launch configuration.
 - Installing the Application (if relevant).
 - Launching the Application with the given configuration.

 @param simulatorConfiguration the Configuration of the Simulator to launch.
 @param simulatorLaunchConfiguration the Launch Configuration for the Simulator.
 @param application the Application to install.
 @param applicationLaunchConfiguration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration launches:(FBSimulatorBootConfiguration *)simulatorLaunchConfiguration thenLaunchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration;

/**
 An Assertion for:
 - Obtaining a Simulator with a given configuration.
 - Launching it with the launch configuration.
 - Installing the Application (if relevant).
 - Launching the Aplication with the given configuration.
 - Relaunching the same Application.

 @param simulatorConfiguration the Configuration of the Simulator to launch.
 @param simulatorLaunchConfiguration the Launch Configuration for the Simulator.
 @param application the Application to install.
 @param applicationLaunchConfiguration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration relaunches:(FBSimulatorBootConfiguration *)simulatorLaunchConfiguration thenLaunchesApplication:(FBApplicationDescriptor *)application withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration;

@end

/**
 Assertion Helpers for FBSimulatorControl Notifications.
 */
@interface FBSimulatorControlNotificationAssertions : NSObject

/**
 Create a Notification Assertions Instance for the provided test case & pool
 */
+ (instancetype)withTestCase:(XCTestCase *)testCase pool:(FBSimulatorPool *)pool;

/**
 Assertion Failure if a notification of the given name isn't the first in the list of received notifications.
 */
- (NSNotification *)consumeNotification:(NSString *)notificationName;

/**
 Assertion Failure if a notification of the given name isn't the first in the list of received notifications.
 Will wait timeout seconds for the notification to appear if there isn't a notification recieved.
 */
- (NSNotification *)consumeNotification:(NSString *)notificationName timeout:(NSTimeInterval)timeout;

/**
 Assertion Failure if all of the notifications don't appear in the list of notifications recieved.s
 Ordering doesn't matter but the notifications must be contiguous.
 */
- (NSNotification *)consumeNotifications:(NSArray *)notificationNames;

/**
 Assertion failure if there are pending notifications.
 */
- (void)noNotificationsToConsume;

/**
 Removes all pending notifications
 */
- (void)consumeAllNotifications;

/**
 Assertion failure if the Notifications that fire on booting haven't been recieved;
 */
- (void)bootingNotificationsFired:(FBSimulatorBootConfiguration *)launchConfiguration;

/**
 Assertion failure if the Notifications that fire on shutdown haven't been recieved;
 */
- (void)shutdownNotificationsFired:(FBSimulatorBootConfiguration *)launchConfiguration;

@end

NS_ASSUME_NONNULL_END
