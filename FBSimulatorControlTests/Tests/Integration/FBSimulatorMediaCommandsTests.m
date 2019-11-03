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

@interface FBSimulatorMediaCommandsTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorMediaCommandsTests

- (void)testPhotoUpload
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  NSError *error = nil;
  BOOL success = [[FBSimulatorMediaCommands commandsWithTarget:simulator] uploadPhotos:@[FBSimulatorControlFixtures.photo0Path, FBSimulatorControlFixtures.photo1Path] error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testVideoUploadSuccess
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  NSError *error = nil;
  BOOL success = [[FBSimulatorMediaCommands commandsWithTarget:simulator] uploadVideos:@[FBSimulatorControlFixtures.video0Path] error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
