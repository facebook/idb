/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorApplicationDescriptorTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorApplicationDescriptorTests

- (void)testCanFetchSimulatorApplications
{
  FBSimulator *simulator = [self assertObtainsSimulator];
  XCTAssertNotNil([FBApplicationDescriptor systemApplicationNamed:@"MobileSafari" simulator:simulator error:nil]);
  XCTAssertNotNil([FBApplicationDescriptor systemApplicationNamed:@"Camera" simulator:simulator error:nil]);
  XCTAssertNotNil([FBApplicationDescriptor systemApplicationNamed:@"Maps" simulator:simulator error:nil]);
}

- (void)testCreatesSampleApplication
{
  FBApplicationDescriptor *application = self.tableSearchApplication;
  XCTAssertEqualObjects(application.bundleID, @"com.example.apple-samplecode.TableSearch");
  XCTAssertEqualObjects(application.binary.architectures, [NSSet setWithArray:@[@"i386"]]);
}

@end
