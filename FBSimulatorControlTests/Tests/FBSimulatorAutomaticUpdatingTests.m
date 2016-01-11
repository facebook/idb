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

@interface FBSimulatorAutomaticUpdatingTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorAutomaticUpdatingTests

- (void)setUp
{
  [super setUp];
}

- (void)testGetsArgumentsOfSimulatorContainerProcess
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  FBProcessInfo *containerProcess = simulator.launchInfo.simulatorProcess;
  XCTAssertNotNil(containerProcess);

  NSSet *arguments = [NSSet setWithArray:containerProcess.arguments];
  XCTAssertTrue([arguments containsObject:session.simulator.udid]);
}

- (void)testUpdatesContainerProcessOnTermination
{
  FBSimulatorSession *session = [self createBootedSession];
  FBSimulator *simulator = session.simulator;

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^{
    return NO;
  }];

  FBProcessInfo *containerApplication = simulator.launchInfo.simulatorProcess;
  XCTAssertNotNil(containerApplication);

  NSRunningApplication *workspaceApplication = [simulator.processQuery runningApplicationForProcess:containerApplication];
  XCTAssertNotNil(workspaceApplication);
  [workspaceApplication forceTerminate];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    return NO;
  }];

  XCTAssertNil(simulator.launchInfo);
}

@end
