/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorHistoryGeneratorTests : XCTestCase

@property (nonatomic, strong, readwrite) FBSimulatorHistoryGenerator *generator;

@end

@implementation FBSimulatorHistoryGeneratorTests

- (void)setUp
{
  FBSimulatorControlTests_SimDevice_Double *device = [FBSimulatorControlTests_SimDevice_Double new];
  device.state = FBSimulatorStateCreating;
  device.UDID = [NSUUID UUID];
  device.name = @"iPhoneMega";

  FBSimulator *simulator = [[FBSimulator alloc] initWithDevice:(id)device configuration:FBSimulatorConfiguration.defaultConfiguration set:[FBSimulatorSet new] processFetcher:[FBSimulatorProcessFetcher new] auxillaryDirectory:NSTemporaryDirectory() logger:nil];
  self.generator = [FBSimulatorHistoryGenerator forSimulator:simulator];
}

- (void)tearDown
{
  self.generator = nil;
}

- (void)assertHistory:(FBSimulatorHistory *)state changes:(NSArray *)changes
{
  NSArray *actualStates = [state.changesToSimulatorState.reverseObjectEnumerator.allObjects valueForKey:@"simulatorState"];
  XCTAssertEqualObjects(actualStates, changes);
}

- (void)testChangesToSimulatorState
{
  [self.generator didChangeState:FBSimulatorStateCreating];
  [self.generator didChangeState:FBSimulatorStateBooting];
  [self.generator didChangeState:FBSimulatorStateBooted];
  [self.generator didChangeState:FBSimulatorStateShuttingDown];
  [self.generator didChangeState:FBSimulatorStateShutdown];

  FBSimulatorHistory *latest = self.generator.history;
  [self assertHistory:latest changes:@[
    @(FBSimulatorStateCreating),
    @(FBSimulatorStateBooting),
    @(FBSimulatorStateBooted),
    @(FBSimulatorStateShuttingDown),
    @(FBSimulatorStateShutdown)
  ]];

  XCTAssertEqual(latest.previousState.previousState, [latest lastChangeOfState:FBSimulatorStateBooted]);
}

@end
