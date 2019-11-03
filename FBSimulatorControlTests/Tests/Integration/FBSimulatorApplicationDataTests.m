/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (void)testDataContainerPath
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  NSError *error;
  BOOL success = [[simulator dataContainerOfApplicationWithBundleID:self.safariAppLaunch.bundleID] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
