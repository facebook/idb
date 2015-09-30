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

@class FBSimulatorControl;
@class FBSimulatorControlNotificationAssertion;

/**
 A Test Case that boostraps a FBSimulatorControl instance.
 Should be overridden to provide Integration tests for Simulators.
 */
@interface FBSimulatorControlTestCase : XCTestCase

/*
 The Per-Test-Case Management Options.
 */
- (FBSimulatorManagementOptions)managementOptions;

@property (nonatomic, strong, readonly) FBSimulatorControl *control;
@property (nonatomic, strong, readonly) FBSimulatorControlNotificationAssertion *notificationAssertion;

@end
