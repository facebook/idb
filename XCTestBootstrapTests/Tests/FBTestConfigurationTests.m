/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBTestConfigurationTests : XCTestCase

@end

@implementation FBTestConfigurationTests

- (void)testSimpleConstructor
{
  NSUUID *sessionIdentifier = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
  FBTestConfiguration *testConfiguration = [FBTestConfiguration
    configurationWithSessionIdentifier:sessionIdentifier
    moduleName:@"Franek"
    testBundlePath:@"BundlePath"
    path:@"ConfigPath"
    uiTesting:YES];

  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.sessionIdentifier, sessionIdentifier);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.testBundlePath, @"BundlePath");
  XCTAssertEqual(testConfiguration.path, @"ConfigPath");
  XCTAssertTrue(testConfiguration.shouldInitializeForUITesting);
}

- (void)testSaveAs
{
  NSError *error;
  NSUUID *sessionIdentifier = NSUUID.UUID;

  FBTestConfiguration *testConfiguration = [FBTestConfiguration
    configurationByWritingToFileWithSessionIdentifier:sessionIdentifier
    moduleName:@"ModuleName"
    testBundlePath:NSTemporaryDirectory()
    uiTesting:YES
    testsToRun:[NSSet set]
    testsToSkip:[NSSet set]
    targetApplicationPath:@"targetAppPath"
    targetApplicationBundleID:@"targetBundleID"
    automationFrameworkPath:nil
    reportActivities:NO
    error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(testConfiguration);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:testConfiguration.path]);
}

@end
