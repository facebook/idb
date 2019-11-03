/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBSimulatorControlTestCase.h"

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorControl;

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
- (void)assertSimulator:(FBSimulator *)simulator isRunningApplicationFromConfiguration:(FBApplicationLaunchConfiguration *)launchConfiguration;

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
- (FBFuture<FBSimulator *> *)assertObtainsSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration;

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
- (nullable FBSimulator *)assertObtainsBootedSimulatorWithInstalledApplication:(FBBundleDescriptor *)application;

/**
 Asserts that a booted Simulator with the provided configurations can be obtained.

 @param configuration the Simulator Configuration to obtain.
 @param bootConfiguration the Simulator Boot Configuration.
 @return a Simulator if succesful, nil otherwise.
 */
- (nullable FBSimulator *)assertObtainsBootedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration bootConfiguration:(FBSimulatorBootConfiguration *)bootConfiguration;

/**
 An Assertion for Installing the Application.

 @param simulator the booted Simulator.
 @param application the Application to install.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator installs:(FBBundleDescriptor *)application;

/**
 An Assertion for Launching the Application with the given configuration.

 @param simulator the booted Simulator.
 @param configuration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator launches:(FBApplicationLaunchConfiguration *)configuration;

/**
 An Assertion for:
 - Obtaining a Simulator with a given configuration.
 - Booting it with the Boot Configuration
 - Launching the Application with the given configuration.

 @param simulatorConfiguration the Configuration of the Simulator to launch.
 @param bootConfiguration the Boot Configuration for the Simulator.
 @param launchConfiguration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration boots:(FBSimulatorBootConfiguration *)bootConfiguration thenLaunchesApplication:(FBApplicationLaunchConfiguration *)launchConfiguration;

/**
 An Assertion for:
 - Obtaining a Simulator with a given configuration.
 - Booting it with the Boot Configuration
 - Launching the Application with the given configuration.
 - Relaunching the same Application.

 @param simulatorConfiguration the Configuration of the Simulator to launch.
 @param bootConfiguration the Boot Configuration for the Simulator.
 @param launchConfiguration the Application to then launch.
 @return a Simulator if successful, nil otherwise.
 */
- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration boots:(FBSimulatorBootConfiguration *)bootConfiguration launchesThenRelaunchesApplication:(FBApplicationLaunchConfiguration *)launchConfiguration;

@end

NS_ASSUME_NONNULL_END
