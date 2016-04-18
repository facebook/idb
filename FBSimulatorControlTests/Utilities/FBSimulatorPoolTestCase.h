/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBSimulator;
@class FBSimulatorPool;
@class FBSimulatorSet;

/**
 A Test Case Template that creates a Set & Pool for mocking.
 */
@interface FBSimulatorPoolTestCase : XCTestCase

/**
 The Pool created after 'createPoolWithExistingSimDeviceSpecs:' is called.
 */
@property (nonatomic, strong, readonly) FBSimulatorPool *pool;

/**
 The Set created after 'createPoolWithExistingSimDeviceSpecs:' is called.
 */
@property (nonatomic, strong, readonly) FBSimulatorSet *set;

/**
 Creates a Simulator Pool with an array of Specs for SimDevices.
 */
- (NSArray<FBSimulator *> *)createPoolWithExistingSimDeviceSpecs:(NSArray<NSDictionary *> *)simulatorSpecs;

/**
 Mocks the Allocation of Simulators based on their UDID.
 */
- (void)mockAllocationOfSimulatorsUDIDs:(NSArray<NSString *> *)deviceUDIDs;

@end
