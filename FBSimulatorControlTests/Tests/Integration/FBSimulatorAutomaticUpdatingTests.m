/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <Foundation/Foundation.h>

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
  // Test only relevant for Simulator.app Launching
  if (FBSimulatorControlTestCase.useDirectLaunching) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBProcessInfo *containerProcess = simulator.containerApplication;
  XCTAssertNotNil(containerProcess);

  NSSet *arguments = [NSSet setWithArray:containerProcess.arguments];
  XCTAssertTrue([arguments containsObject:simulator.udid]);
}

- (void)testUpdatesContainerProcessOnTermination
{
  // Test only relevant for Simulator.app Launching
  if (FBSimulatorControlTestCase.useDirectLaunching) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBProcessInfo *containerApplication = simulator.containerApplication;
  XCTAssertNotNil(containerApplication);

  NSRunningApplication *workspaceApplication = [simulator.processFetcher.processFetcher runningApplicationForProcess:containerApplication];
  XCTAssertNotNil(workspaceApplication);
  [workspaceApplication forceTerminate];

  [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    return NO;
  }];

  XCTAssertNil(simulator.containerApplication);
}

@end
