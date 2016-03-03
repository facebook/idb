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

@interface FBSimulatorInteractionTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorInteractionTests

- (void)testPhotoUpload
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  [self assertInteractionSuccessful:[simulator.interact uploadPhotos:@[FBSimulatorControlFixtures.photo0Path, FBSimulatorControlFixtures.photo1Path]]];
}

- (void)testVideoUploadSuccess
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  [self assertInteractionSuccessful:[simulator.interact uploadVideos:@[FBSimulatorControlFixtures.video0Path]]];
}

- (void)testVideoUploadFailure
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  [self assertInteractionFailed:[simulator.interact uploadVideos:@[FBSimulatorControlFixtures.photo0Path]]];
}

@end
