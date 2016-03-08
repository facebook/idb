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

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"

@interface FBDiagnosticTests : XCTestCase

@end

@implementation FBDiagnosticTests

- (void)testBuilderBuilds
{
  NSData *data = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[[[[FBDiagnosticBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:data]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"shortname");
  XCTAssertEqualObjects(diagnostic.fileType, @"filetype");
  XCTAssertEqualObjects(diagnostic.humanReadableName, @"human");
  XCTAssertEqualObjects(diagnostic.asData, data);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBuilderReplacesExistingProperties
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[[[[FBDiagnosticBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:firstData]
    build];

  NSData *secondData = [@"SOME NEW DATA" dataUsingEncoding:NSUTF8StringEncoding];

  diagnostic = [[[[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateShortName:@"newshortname"]
    updateFileType:@"newfiletype"]
    updateHumanReadableName:@"newhuman"]
    updateData:secondData]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"newshortname");
  XCTAssertEqualObjects(diagnostic.fileType, @"newfiletype");
  XCTAssertEqualObjects(diagnostic.humanReadableName, @"newhuman");
  XCTAssertEqualObjects(diagnostic.asData, secondData);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBuilderReplacesStringsAndData
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updateData:firstData]
    build];

  diagnostic = [[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateString:@"A String"]
    build];

  XCTAssertEqualObjects(diagnostic.asData, [@"A String" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(diagnostic.asString, @"A String");

  diagnostic = [[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updateString:@"Not me ever"]
    updateData:[@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]]
    build];

  XCTAssertEqualObjects(diagnostic.asData, [@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(diagnostic.asString, @"I am now over here");
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testStringAccessorReadsFromFile
{
  NSString *logString = @"FOO BAR BAZ";
  NSString *logPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"testBuilderReadsFromFile"] stringByAppendingPathExtension:@"txt"];
  [logString writeToFile:logString atomically:YES encoding:NSUTF8StringEncoding error:nil];

  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updatePath:logPath]
    build];

  XCTAssertEqualObjects(diagnostic.asString, diagnostic.asString);
}

- (void)testReadingPathWritesToFile
{
  NSString *logString = @"FOO BAR BAZ";

  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateString:logString]
    updateShortName:@"ballooon"]
    build];

  NSString *writeOutString = [NSString stringWithContentsOfFile:diagnostic.asPath usedEncoding:nil error:nil];

  XCTAssertEqualObjects(writeOutString, logString);
}

- (void)testTextFileCoercions
{
  FBDiagnostic *diagnostic = self.simulatorSystemLog;

  XCTAssertNotNil(diagnostic.asPath);
  [self assertNeedle:@"layer position 375 667 bounds 0 0 750 1334" inHaystack:diagnostic.asString];
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBinaryFileCoercions
{
  FBDiagnostic *diagnostic = self.photoDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asString);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertFalse(diagnostic.isSearchableAsText);
}

- (void)testJSONNativeObjectCoercions
{
  NSString *substring = @"FOO BAR BAAAA";
  id json = @{
    @"bing" : @"bong",
    @"animal" : @"cat",
    @"somes" : @[
      @1, @2, @3, @4, substring
    ],
  };
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"somelog"]
    updateJSONSerializable:json]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  [self assertNeedle:substring inHaystack:diagnostic.asString];
  XCTAssertEqualObjects(diagnostic.asJSON, json);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testJSONDataCoercions
{
  NSString *substring = @"FOO BAR BAAAA";
  id json = @{
    @"bing" : @"bong",
    @"animal" : @"cat",
    @"somes" : @[
      @1, @2, @3, @4, substring
    ],
  };
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:nil];
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"somelog"]
    updateData:jsonData]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  [self assertNeedle:substring inHaystack:diagnostic.asString];
  XCTAssertEqualObjects(diagnostic.asJSON, json);
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testJSONFileCoercions
{
  FBDiagnostic *diagnostic = self.treeJSONDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  [self assertNeedle:@"Swipe down with three fingers to reveal the notification center" inHaystack:diagnostic.asString];
  XCTAssertEqualObjects([[[diagnostic.asJSON objectForKey:@"value"] objectForKey:@"tree"] objectForKey:@"name"], @"SpringBoard");
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testJSONSerializableCoercions
{
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"applaunch"]
    updateJSONSerializable:self.appLaunch1]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  [self assertNeedle:@"com.example.apple-samplecode.TableSearch" inHaystack:diagnostic.asString];
  XCTAssertEqualObjects([[diagnostic.asJSON objectForKey:@"environment"] objectForKey:@"FOO"], @"BAR");
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

@end
