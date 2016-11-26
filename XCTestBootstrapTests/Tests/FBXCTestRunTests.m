/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBXCTestRunTests : XCTestCase

@end

@implementation FBXCTestRunTests

- (void)setUp
{
  [super setUp];

  NSError *error;
  // TODO: <plu> Remove this once the framework loading is put in the correct place.
  [XCTestBootstrapFrameworkLoader loadPrivateFrameworks:nil error:&error];
  XCTAssertNil(error);
}

- (void)testValidTestRunConfiguration
{
  NSError *error;
  FBXCTestRun *testRun = [[FBXCTestRun
    withTestRunFileAtPath:[FBXCTestRunTests sampleXCTestRunPath]]
    buildWithError:&error];

  XCTAssertNil(error);
  XCTAssertEqual(testRun.targets.count, 2u);

  FBXCTestRunTarget *firstTarget = testRun.targets.firstObject;
  XCTAssertEqualObjects(firstTarget.testLaunchConfiguration.testHostPath.lastPathComponent, @"Sample.app");
  XCTAssertEqual(firstTarget.applications.count, 1u);
  XCTAssertEqualObjects(firstTarget.applications.firstObject.bundleID, @"com.facebook.Sample");

  FBXCTestRunTarget *lastTarget = testRun.targets.lastObject;
  XCTAssertEqualObjects(lastTarget.testLaunchConfiguration.testHostPath.lastPathComponent, @"SampleUITests-Runner.app");
  XCTAssertEqual(lastTarget.applications.count, 2u);
  XCTAssertEqualObjects(lastTarget.applications.firstObject.bundleID, @"com.apple.test.SampleUITests-Runner");
  XCTAssertEqualObjects(lastTarget.applications.lastObject.bundleID, @"com.facebook.Sample");
}

- (void)testInvalidTestRunConfigurationPath
{
  NSError *error;
  FBXCTestRun *testRun = [[FBXCTestRun
    withTestRunFileAtPath:@"/tmp/doesntexist.xctestrun"]
    buildWithError:&error];
  XCTAssertNotNil(error);
  XCTAssertNil(testRun);
}

@end
