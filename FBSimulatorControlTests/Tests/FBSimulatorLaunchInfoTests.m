/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <AppKit/AppKit.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorLaunchInfoTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorLaunchInfoTests

- (void)setUp
{
  [super setUp];
}

- (void)testGetsArgumentsOfBootedProcess
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  FBProcessInfo *process = simulator.launchInfo.simulatorProcess;
  XCTAssertNotNil(simulator.launchInfo.simulatorProcess);

  NSSet *arguments = [NSSet setWithArray:process.arguments];
  XCTAssertTrue([arguments containsObject:session.simulator.udid]);
}

- (void)testUpdatesTerminationInformation
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:3 untilTrue:^BOOL{
    return NO;
  }];

  NSRunningApplication *application = simulator.launchInfo.simulatorApplication;
  XCTAssertNotNil(application);
  [application terminate];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:3 untilTrue:^BOOL{
    return NO;
  }];

  XCTAssertNil(simulator.launchInfo);
}

@end
