/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBSimulator;
@class FBSimulatorSet;

/**
 A Test Case Template that creates a Set for mocking.
 */
@interface FBSimulatorSetTestCase : XCTestCase

/**
 The Set created after 'createSetWithExistingSimDeviceSpecs:' is called.
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 Creates a Simulator Pool with an array of Specs for SimDevices.
 */
- (NSArray<FBSimulator *> *)createSetWithExistingSimDeviceSpecs:(NSArray<NSDictionary<NSString *, id> *> *)simulatorSpecs;

@end
