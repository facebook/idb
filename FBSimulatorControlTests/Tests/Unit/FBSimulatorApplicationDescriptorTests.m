/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  XCTAssertNotNil([FBBundleDescriptor systemApplicationNamed:@"MobileSafari" simulator:simulator error:nil]);
  XCTAssertNotNil([FBBundleDescriptor systemApplicationNamed:@"Camera" simulator:simulator error:nil]);
  XCTAssertNotNil([FBBundleDescriptor systemApplicationNamed:@"Maps" simulator:simulator error:nil]);
}

- (void)testCreatesSampleApplication
{
  FBBundleDescriptor *application = self.tableSearchApplication;
  XCTAssertEqualObjects(application.identifier, @"com.example.apple-samplecode.TableSearch");
  XCTAssertEqualObjects(application.binary.architectures, ([NSSet setWithArray:@[@"i386", @"x86_64"]]));
}

@end
