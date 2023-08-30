/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import <XCTestBootstrap/XCTestBootstrap.h>
#import <XCTestPrivate/XCTestConfiguration.h>
#import <XCTestPrivate/XCTCapabilities.h>

@interface FBTestConfigurationTests : XCTestCase

@end

@implementation FBTestConfigurationTests

- (void)testSimpleConstructor
{
  XCTestConfiguration * xcTestConfig = [objc_lookUpClass("XCTestConfiguration") new];
  NSUUID *sessionIdentifier = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
  FBTestConfiguration *testConfiguration = [FBTestConfiguration
    configurationWithSessionIdentifier:sessionIdentifier
    moduleName:@"Franek"
    testBundlePath:@"BundlePath"
    path:@"ConfigPath"
    uiTesting:YES
    xcTestConfiguration:xcTestConfig];

  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.sessionIdentifier, sessionIdentifier);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.testBundlePath, @"BundlePath");
  XCTAssertEqual(testConfiguration.path, @"ConfigPath");
  XCTAssertTrue(testConfiguration.shouldInitializeForUITesting);
  XCTAssertEqual(testConfiguration.xcTestConfiguration, xcTestConfig);
    
}

- (void)testSaveAs
{
  NSError *error;
  NSUUID *sessionIdentifier = NSUUID.UUID;
  NSString *someRandomPath = NSTemporaryDirectory();

  FBTestConfiguration *testConfiguration = [FBTestConfiguration
    configurationByWritingToFileWithSessionIdentifier:sessionIdentifier
    moduleName:@"ModuleName"
    testBundlePath:someRandomPath
    uiTesting:YES
    testsToRun:[NSSet set]
    testsToSkip:[NSSet set]
    targetApplicationPath:@"targetAppPath"
    targetApplicationBundleID:@"targetBundleID"
    testApplicationDependencies: nil
    automationFrameworkPath:nil
    reportActivities:NO
    error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(testConfiguration);
  XCTAssertTrue([NSFileManager.defaultManager fileExistsAtPath:testConfiguration.path]);

  XCTestConfiguration *xcTestConfig = testConfiguration.xcTestConfiguration;

  XCTAssertNotNil(xcTestConfig);
  XCTAssertEqual(xcTestConfig.productModuleName, @"ModuleName");
  XCTAssertEqualObjects(xcTestConfig.testBundleURL, [NSURL fileURLWithPath:someRandomPath]);
  XCTAssertEqual(xcTestConfig.initializeForUITesting, YES);
  XCTAssertEqual(xcTestConfig.targetApplicationPath, @"targetAppPath");
  XCTAssertEqual(xcTestConfig.targetApplicationBundleID, @"targetBundleID");
  XCTAssertEqual(xcTestConfig.reportActivities, NO);
  XCTAssertEqual(xcTestConfig.reportResultsToIDE, YES);
  
  NSDictionary *capabilities = @{@"XCTIssue capability": @1, @"ubiquitous test identifiers": @1};
  XCTAssertEqualObjects(xcTestConfig.IDECapabilities.capabilitiesDictionary, capabilities);
}

@end
