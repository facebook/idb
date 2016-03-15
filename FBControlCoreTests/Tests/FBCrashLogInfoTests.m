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

#import "FBControlCoreFixtures.h"

@interface FBCrashLogInfoTests : XCTestCase

@end

@implementation FBCrashLogInfoTests

- (void)testAssetsdCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 39942);
  XCTAssertEqual(info.parentProcessIdentifier, 39927);
  XCTAssertEqualObjects(info.processName, @"assetsd");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Applications/xcode_7.2.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk/System/Library/Frameworks/AssetsLibrary.framework/Support/assetsd");
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeSystem);
}

- (void)testAgentCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.agentCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 39655);
  XCTAssertEqual(info.parentProcessIdentifier, 39576);
  XCTAssertEqualObjects(info.processName, @"WebDriverAgent");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Users/USER/*/WebDriverAgent");
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeCustomAgent);
}

- (void)testAppDefaultSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithDefaultDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 37083);
  XCTAssertEqual(info.parentProcessIdentifier, 37007);
  XCTAssertEqualObjects(info.processName, @"TableSearch");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/Users/USER/Library/Developer/CoreSimulator/Devices/2FF8DD07-20B7-4D04-97F0-092DF61CD3C3/data/Containers/Bundle/Application/2BF2C731-1965-497D-B3E2-E347BD7BF464/TableSearch.app/TableSearch");
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeApplication);
}

- (void)testAppCustomSet
{
  FBCrashLogInfo *info = [FBCrashLogInfo fromCrashLogAtPath:FBControlCoreFixtures.appCrashPathWithCustomDeviceSet];
  XCTAssertNotNil(info);
  XCTAssertEqual(info.processIdentifier, 40119);
  XCTAssertEqual(info.parentProcessIdentifier, 39927);
  XCTAssertEqualObjects(info.processName, @"TableSearch");
  XCTAssertEqualObjects(info.parentProcessName, @"launchd_sim");
  XCTAssertEqualObjects(info.executablePath, @"/private/var/folders/*/TableSearch.app/TableSearch");
  XCTAssertEqual(info.processType, FBCrashLogInfoProcessTypeApplication);
}

@end
