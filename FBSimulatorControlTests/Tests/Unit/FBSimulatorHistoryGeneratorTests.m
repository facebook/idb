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

  FBSimulator *simulator = [[FBSimulator alloc] initWithDevice:(id)device configuration:nil set:nil processFetcher:nil auxillaryDirectory:NSTemporaryDirectory() logger:nil];
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

- (void)testLastAppLaunch
{
  [self.generator applicationDidLaunch:self.appLaunch1 didStart:self.processInfo1];
  [self.generator applicationDidTerminate:self.processInfo1 expected:YES];
  [self.generator applicationDidLaunch:self.appLaunch2 didStart:self.processInfo2];
  FBApplicationLaunchConfiguration *lastLaunchedApp = self.generator.history.lastLaunchedApplication;

  XCTAssertNotNil(lastLaunchedApp);
  XCTAssertNotEqualObjects(self.appLaunch1, lastLaunchedApp);
  XCTAssertEqualObjects(self.appLaunch2, lastLaunchedApp);
}

- (void)testRecencyOfApplicationLaunchConfigurations
{
  [self.generator applicationDidLaunch:self.appLaunch1 didStart:self.processInfo1];
  [self.generator applicationDidLaunch:self.appLaunch2 didStart:self.processInfo2];
  [self.generator applicationDidLaunch:self.appLaunch2 didStart:self.processInfo2a];

  XCTAssertEqualObjects(self.generator.history.allApplicationLaunches, (@[self.appLaunch2, self.appLaunch2, self.appLaunch1]));
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
