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
