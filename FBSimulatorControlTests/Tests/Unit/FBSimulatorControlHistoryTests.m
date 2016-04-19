/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorControlHistoryTests : XCTestCase

@property (nonatomic, strong, readwrite) FBSimulatorHistoryGenerator *generator;

@end

@implementation FBSimulatorControlHistoryTests

- (void)setUp
{
  FBSimulatorControlTests_SimDevice_Double *device = [FBSimulatorControlTests_SimDevice_Double new];
  device.state = FBSimulatorStateCreating;
  device.UDID = [NSUUID UUID];
  device.name = @"iPhoneMega";

  FBSimulator *simulator = [[FBSimulator alloc] initWithDevice:(id)device configuration:nil set:nil processFetcher:nil auxillaryDirectory:NSTemporaryDirectory() logger:nil];
  self.generator = [FBSimulatorHistoryGenerator forSimulator:simulator];
}

- (void)tearDown
{
  self.generator = nil;
}

- (void)testHistoryCanBeArchived
{
  [self.generator applicationDidLaunch:self.appLaunch2 didStart:self.processInfo2];
  [self.generator applicationDidLaunch:self.appLaunch1 didStart:self.processInfo1];

  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.generator.history];
  FBSimulatorHistory *history = [NSKeyedUnarchiver unarchiveObjectWithData:data];

  XCTAssertEqualObjects(history.lastLaunchedApplicationProcess, self.processInfo1);
}

@end
