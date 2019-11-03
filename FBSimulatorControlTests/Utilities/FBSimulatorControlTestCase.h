/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulatorBootConfiguration;
@class FBSimulatorConfiguration;
@class FBSimulatorControl;
@class FBSimulatorControlNotificationAssertions;

/**
 Environment Keys and Values for how the Simulator should be launched.
 */
extern NSString *const FBSimulatorControlTestsLaunchTypeEnvKey;
extern NSString *const FBSimulatorControlTestsLaunchTypeSimulatorApp;
extern NSString *const FBSimulatorControlTestsLaunchTypeDirect;

/**
 The default models for integration tests.
 */
#define SimulatorControlTestsDefaultiPhoneModel FBDeviceModeliPhone6S
#define SimulatorControlTestsDefaultiPadModel FBDeviceModeliPadAir

/**
 A Test Case that boostraps a FBSimulatorControl instance.
 Should be overridden to provide Integration tests for Simulators.
 */
@interface FBSimulatorControlTestCase : XCTestCase

/**
 The Per-TestCase Management Options for created FBSimulatorControl instances.
 */
@property (nonatomic, assign, readwrite) FBSimulatorManagementOptions managementOptions;

/**
 A default Simulator Configuration.
 */
@property (nonatomic, strong, readwrite) FBSimulatorConfiguration *simulatorConfiguration;

/**
 A default Simulator Launch Configuration.
 */
@property (nonatomic, strong, readwrite) FBSimulatorBootConfiguration *bootConfiguration;

/**
 The Per-Test-Case Device Set Path.
 */
@property (nonatomic, copy, readwrite) NSString *deviceSetPath;

/**
 The Simulator Control instance that is lazily created from the defaults
 */
@property (nonatomic, strong, readonly) FBSimulatorControl *control;

/**
 Some tests are flakier on travis, this is a temporary way of disabling them until they are improved.
 */
+ (BOOL)isRunningOnTravis;

/**
 Whether or not Simulators should be launched directly or via the Simulator.app.
 */
+ (BOOL)useDirectLaunching;

@end

NS_ASSUME_NONNULL_END
