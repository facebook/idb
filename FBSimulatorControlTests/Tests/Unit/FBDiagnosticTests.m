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
  XCTAssertTrue(diagnostic.isSearchableAsText);
}

- (void)testBinaryFileCoercions
{
  FBDiagnostic *diagnostic = self.photoDiagnostic;

  XCTAssertNotNil(diagnostic.asPath);
  XCTAssertNotNil(diagnostic.asData);
  XCTAssertNil(diagnostic.asString);
  XCTAssertFalse(diagnostic.isSearchableAsText);
}

@end
