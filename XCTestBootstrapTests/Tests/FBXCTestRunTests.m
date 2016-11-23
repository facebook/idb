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
  [XCTestBootstrapFrameworkLoader loadPrivateFrameworks:nil error:&error];
  XCTAssertNil(error);
}

- (void)testValidTestRunConfiguration
{
  NSError *error;
  FBXCTestRun *testRun = [[FBXCTestRun
    withTestRunFileAtPath:[FBXCTestRunTests tableSearchXCTestRunPath]]
    buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(testRun.testHostPath);
  XCTAssertNotNil(testRun.testBundlePath);
  XCTAssertEqualObjects(testRun.arguments, (@[@"ARG1", @"ARG2", @"ARG3"]));
  XCTAssertEqualObjects(testRun.environment[@"FOO"], @"BAR");
  XCTAssertEqualObjects(testRun.environment[@"BLA"], @"FASEL");
  XCTAssertEqualObjects(testRun.testsToSkip, [NSSet setWithObject:@"TableSearchTests/testSkipMe"]);
  XCTAssertEqualObjects(testRun.testsToRun, [NSSet set]);
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
