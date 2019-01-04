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

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBTestBundleTests : XCTestCase
@end

@implementation FBTestBundleTests

- (void)testTestBundleLoadWithPath
{
  NSUUID *sessionIdentifier = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
  NSBundle *bundle = [FBTestBundleTests iosUnitTestBundleFixture];

  NSError *error;
  FBTestBundle *testBundle = [[[[[[[FBTestBundleBuilder
    builder]
    withBinaryName:@"FooApp"]
    withBundleID:@"com.foo.app"]
    withBundlePath:bundle.bundlePath]
    withWorkingDirectory:NSTemporaryDirectory()]
    withSessionIdentifier:sessionIdentifier]
    buildWithError:&error];

  XCTAssertNil(error);
  XCTAssertTrue([testBundle isKindOfClass:FBTestBundle.class]);
  XCTAssertTrue([testBundle.configuration.testBundlePath hasSuffix:@"iOSUnitTestFixture.xctest"]);
  XCTAssertTrue([testBundle.configuration.path hasSuffix:@"iOSUnitTestFixture.xctest/iOSUnitTestFixture-E621E1F8-C36C-495A-93FC-0C247A3E6E5F.xctestconfiguration"]);
  XCTAssertNotNil(testBundle.configuration);
  XCTAssertEqualObjects(testBundle.configuration.sessionIdentifier, sessionIdentifier);
  XCTAssertEqualObjects(testBundle.configuration.moduleName, @"iOSUnitTestFixture");
}

- (void)testNoBundlePath
{
  XCTAssertThrows([[FBTestBundleBuilder builder] buildWithError:nil]);
}

- (void)testBundleWithoutSessionIdentifier
{
  NSError *error;
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  FBTestBundle *testBundle = [[[FBTestBundleBuilder
    builder]
    withBundlePath:bundle.bundlePath]
    buildWithError:&error];

  XCTAssertNil(error);
  XCTAssertTrue([testBundle isKindOfClass:FBTestBundle.class]);
  XCTAssertNil(testBundle.configuration);
}

@end
