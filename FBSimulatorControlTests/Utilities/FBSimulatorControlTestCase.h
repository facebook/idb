/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>

@class FBSimulator;
@class FBSimulatorConfiguration;
@class FBSimulatorControl;
@class FBSimulatorControlNotificationAssertions;
@class FBSimulatorLaunchConfiguration;

/**
 Environment Keys and Values for how the Simulator should be launched.
 */
extern NSString *const FBSimulatorControlTestsLaunchTypeEnvKey;
extern NSString *const FBSimulatorControlTestsLaunchTypeSimulatorApp;
extern NSString *const FBSimulatorControlTestsLaunchTypeDirect;

/**
 A Test Case that boostraps a FBSimulatorControl instance.
 Should be overridden to provide Integration tests for Simulators.
 */
@interface FBSimulatorControlTestCase : XCTestCase

/**
 Creates a Session with the provided configuration.
 */
- (FBSimulator *)obtainSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration;

/**
 Creates a Session with the default configuration.
 */
- (FBSimulator *)obtainSimulator;

/**
 Create a Session with a booted Simulator of the default configuration.
 */
- (FBSimulator *)obtainBootedSimulator;

/**
 The Per-TestCase Management Options for created FBSimulatorControl instances.
 */
@property (nonatomic, assign, readwrite) FBSimulatorManagementOptions managementOptions;

/**
 The Per Test Case Allocation Options for created allocated Simulators/Sessions.
 */
@property (nonatomic, assign, readwrite) FBSimulatorAllocationOptions allocationOptions;

/**
 A default Simulator Configuration.
 */
@property (nonatomic, strong, readwrite) FBSimulatorConfiguration *simulatorConfiguration;

/**
 A default Simulator Launch Configuration.
 */
@property (nonatomic, strong, readwrite) FBSimulatorLaunchConfiguration *simulatorLaunchConfiguration;

/**
 The Per-Test-Case Device Set Path.
 */
@property (nonatomic, copy, readwrite) NSString *deviceSetPath;

/**
 The Simulator Control instance that is lazily created from the defaults
 */
@property (nonatomic, strong, readonly) FBSimulatorControl *control;

/**
 The FBSimulatorControlAssertions instance
 */
@property (nonatomic, strong, readonly) FBSimulatorControlNotificationAssertions *assert;

/**
 Some tests are flakier on travis, this is a temporary way of disabling them until they are improved.
 */
+ (BOOL)isRunningOnTravis;

/**
 Whether or not Simulators should be launched directly or via the Simulator.app.
 */
+ (BOOL)useDirectLaunching;

@end
