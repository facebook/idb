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

#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorTests

- (void)flaky_testCanInferProcessIdentiferAppropriately
{
  FBSimulatorSession *session = [self createBootedSession];

  NSInteger expected = session.simulator.processIdentifier;
  XCTAssertTrue(expected > 1);
  session.simulator.processIdentifier = -1;
  NSInteger actual = session.simulator.processIdentifier;
  XCTAssertEqual(expected, actual);
}

@end
