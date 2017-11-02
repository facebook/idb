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

@interface FBSimulatorApplicationDataTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorApplicationDataTests

- (void)testRelocatesFile
{
  NSString *fixturePath = FBSimulatorControlFixtures.photo0Path;
  FBSimulator *simulator = [self assertObtainsBootedSimulator];

  NSError *error = nil;
  BOOL success = [[simulator
    copyDataAtPath:fixturePath
    toContainerOfApplication:self.safariAppLaunch.bundleID
    atContainerPath:@"Documents"]
    await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSString *destinationPath = [NSTemporaryDirectory() stringByAppendingPathComponent:fixturePath.lastPathComponent];
  success = [[simulator
   copyDataFromContainerOfApplication:self.safariAppLaunch.bundleID
   atContainerPath:[@"Documents" stringByAppendingPathComponent:fixturePath.lastPathComponent]
   toDestinationPath:destinationPath]
   await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
