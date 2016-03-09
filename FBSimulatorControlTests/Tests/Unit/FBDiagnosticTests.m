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

- (NSString *)temporaryOutputFile
{
  return [[NSTemporaryDirectory() stringByAppendingPathComponent:@"FBDiagnosticTests"] stringByAppendingPathExtension:@"tempout"];
}

- (void)assertWritesOutToFile:(FBDiagnostic *)diagnostic
{
  NSString *outFile = self.temporaryOutputFile;
  NSError *error = nil;
  BOOL success = [diagnostic writeOutToPath:outFile error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSData *readData = [[[[FBDiagnosticBuilder builderWithDiagnostic:diagnostic]
    updatePath:outFile]
    build]
    asData];
  XCTAssertEqualObjects(diagnostic.asData, readData);
}

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
  NSString *logPath = self.temporaryOutputFile;
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

- (void)testInitializesDefaultsWhenPopulatingFromFile
{
  FBDiagnostic *diagnostic = [[[FBDiagnosticBuilder builder]
    updatePath:FBSimulatorControlFixtures.simulatorSystemLogPath]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"simulator_system");
  XCTAssertEqualObjects(diagnostic.fileType, @"log");
}

- (void)testDoesNotInitializeDefaultsWhenAlreadySpecified
{
  FBDiagnostic *diagnostic = [[[[[FBDiagnosticBuilder builder]
    updateShortName:@"bibble"]
    updateFileType:@"txt"]
    updatePath:FBSimulatorControlFixtures.simulatorSystemLogPath]
    build];

  XCTAssertEqualObjects(diagnostic.shortName, @"bibble");
  XCTAssertEqualObjects(diagnostic.fileType, @"txt");
}

- (void)testTextFileCoercions
{
  FBDiagnostic *diagnostic = self.simulatorSystemLog;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  [self assertNeedle:@"layer position 375 667 bounds 0 0 750 1334" inHaystack:diagnostic.asString];
  [self assertWritesOutToFile:diagnostic];
}

- (void)testBinaryFileCoercions
{
  FBDiagnostic *diagnostic = self.photoDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asString);
  XCTAssertNil(diagnostic.asJSON);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertFalse(diagnostic.isSearchableAsText);
  [self assertWritesOutToFile:diagnostic];
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
  XCTAssertEqualObjects(diagnostic.asJSON, json);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  [self assertNeedle:substring inHaystack:diagnostic.asString];
  [self assertWritesOutToFile:diagnostic];
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
  XCTAssertEqualObjects(diagnostic.asJSON, json);
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  [self assertNeedle:substring inHaystack:diagnostic.asString];
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONFileCoercions
{
  FBDiagnostic *diagnostic = self.treeJSONDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects([[[diagnostic.asJSON objectForKey:@"value"] objectForKey:@"tree"] objectForKey:@"name"], @"SpringBoard");
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  [self assertNeedle:@"Swipe down with three fingers to reveal the notification center" inHaystack:diagnostic.asString];
  [self assertWritesOutToFile:diagnostic];
}

- (void)testJSONSerializableCoercions
{
  FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
    updateShortName:@"applaunch"]
    updateJSONSerializable:self.appLaunch1]
    build];

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertEqualObjects([[diagnostic.asJSON objectForKey:@"environment"] objectForKey:@"FOO"], @"BAR");
  XCTAssertTrue(diagnostic.hasLogContent);
  XCTAssertTrue(diagnostic.isSearchableAsText);
  [self assertNeedle:@"com.example.apple-samplecode.TableSearch" inHaystack:diagnostic.asString];
  [self assertWritesOutToFile:diagnostic];
}

@end
