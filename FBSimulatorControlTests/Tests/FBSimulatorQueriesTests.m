/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulator+Private.h>
#import <FBSimulatorControl/FBSimulator+Queries.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBSimulatorSessionLifecycle.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/FBSimulatorSessionState.h>

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorQueriesTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorQueriesTests

- (void)flaky_testCanInferProcessIdentiferAppropriately
{
  FBSimulatorSession *session = [self createBootedSession];

  NSInteger expected = session.simulator.processIdentifier;
  XCTAssertTrue(expected > 1);
  session.simulator.processIdentifier = -1;
  NSInteger actual = session.simulator.processIdentifier;
  XCTAssertEqual(expected, actual);
}

- (void)testCanFindApplicationHome
{
  FBSimulatorSession *session = [self createBootedSessionWithUserApplication];
  FBUserLaunchedProcess *process = session.state.runningApplications.firstObject;
  XCTAssertNotNil(process);

  NSString *path = [session.simulator pathToApplicationHome:process];
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:path]);
}

@end
