/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"

@interface FBCrashLogInfoTests : XCTestCase

@end

@implementation FBCrashLogInfoTests

+ (NSArray<FBCrashLogInfo *> *)allCrashLogs
{
  return @[
    [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet],
    [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.agentCrashPathWithCustomDeviceSet],
    [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithDefaultDeviceSet],
    [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithCustomDeviceSet],
  ];
}

- (void)testAssetsdCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 39942);
  XCTAssertEqual(info.parentProcessIdentifier, 39927);
  XCTAssertEqualObjects(info.identifier, @"assetsd");
  XCTAssertEqualObjects(info.processName, @"assetsd");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Applications/xcode_7.2.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/AssetsLibrary.framework/Support/assetsd");
  XCTAssertEqualWithAccuracy(info.date.timeIntervalSinceReferenceDate, 479723902, 1);
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeSystem);
}

- (void)testAgentCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.agentCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 39655);
  XCTAssertEqual(info.parentProcessIdentifier, 39576);
  XCTAssertEqualObjects(info.identifier, @"WebDriverAgent");
  XCTAssertEqualObjects(info.processName, @"WebDriverAgent");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Users/USER/*/WebDriverAgent");
  XCTAssertEqualWithAccuracy(info.date.timeIntervalSinceReferenceDate, 479723798, 1);
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeCustomAgent);
}

- (void)testAppDefaultSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithDefaultDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 37083);
  XCTAssertEqual(info.parentProcessIdentifier, 37007);
  XCTAssertEqualObjects(info.identifier, @"TableSearch");
  XCTAssertEqualObjects(info.processName, @"TableSearch");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Users/USER/Library/Developer/CoreSimulator/Devices/2FF8DD07-20B7-4D04-97F0-092DF61CD3C3/data/Containers/Bundle/Application/2BF2C731-1965-497D-B3E2-E347BD7BF464/TableSearch.app/TableSearch");
  XCTAssertEqualWithAccuracy(info.date.timeIntervalSinceReferenceDate, 479723201, 1);
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeApplication);
}

- (void)testAppCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 40119);
  XCTAssertEqual(info.parentProcessIdentifier, 39927);
  XCTAssertEqualObjects(info.identifier, @"TableSearch");
  XCTAssertEqualObjects(info.processName, @"TableSearch");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/private/var/folders/*/TableSearch.app/TableSearch");
  XCTAssertEqualWithAccuracy(info.date.timeIntervalSinceReferenceDate, 479723902, 1);
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeApplication);
}

- (void)testIdentifierPredicate
{
  NSArray<FBCrashLogInfo *> *crashes = [FBCrashLogInfoTests.allCrashLogs filteredArrayUsingPredicate:[FBCrashLogInfo predicateForIdentifier:@"assetsd"]];
  XCTAssertEqual(crashes.count, 1u);
}

- (void)testNamePredicate
{
  NSArray<FBCrashLogInfo *> *crashes = [FBCrashLogInfoTests.allCrashLogs filteredArrayUsingPredicate:[FBCrashLogInfo predicateForName:@"assetsd_custom_set.crash"]];
  XCTAssertEqual(crashes.count, 1u);
}

@end
