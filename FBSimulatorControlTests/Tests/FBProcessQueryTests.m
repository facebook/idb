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

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBProcessQueryTests : FBSimulatorControlTestCase

@property (nonatomic, strong, readwrite) FBProcessQuery *query;

@end

@implementation FBProcessQueryTests

- (void)setUp
{
  [super setUp];
  self.query = [FBProcessQuery new];
}

- (void)testGetsUDIDOfBootedSimulator
{
  FBSimulatorSession *session = [self createBootedSession];
  id<FBProcessInfo> process = [self.query processInfoFor:session.simulator.processIdentifier];
  XCTAssertNotNil(process);
  NSSet *arguments = [NSSet setWithArray:process.arguments];
  XCTAssertTrue([arguments containsObject:session.simulator.udid]);
}

@end
