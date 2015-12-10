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

#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorApplicationTests : XCTestCase

@end

@implementation FBSimulatorApplicationTests

- (void)testCanFetchSimulatorApplications
{
  XCTAssertNotNil([FBSimulatorApplication systemApplicationNamed:@"MobileSafari" error:nil]);
  XCTAssertNotNil([FBSimulatorApplication systemApplicationNamed:@"Camera" error:nil]);
  XCTAssertNotNil([FBSimulatorApplication systemApplicationNamed:@"Maps" error:nil]);
}

- (void)testCreatesSampleApplication
{
  FBSimulatorApplication *application = self.tableSearchApplication;
  XCTAssertEqualObjects(application.bundleID, @"com.example.apple-samplecode.TableSearch");
  XCTAssertEqualObjects(application.binary.architectures, [NSSet setWithArray:@[@"i386"]]);
}

@end
