/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import "FBWritableLog.h"

@interface FBWritableLogTests : XCTestCase

@end

@implementation FBWritableLogTests

- (void)testBuilderBuilds
{
  NSData *data = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBWritableLog *writableLog = [[[[[[FBWritableLogBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:data]
    build];

  XCTAssertEqualObjects(writableLog.shortName, @"shortname");
  XCTAssertEqualObjects(writableLog.fileType, @"filetype");
  XCTAssertEqualObjects(writableLog.humanReadableName, @"human");
  XCTAssertEqualObjects(writableLog.asData, data);
}

- (void)testBuilderReplacesExistingProperties
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBWritableLog *writableLog = [[[[[[FBWritableLogBuilder builder]
    updateShortName:@"shortname"]
    updateFileType:@"filetype"]
    updateHumanReadableName:@"human"]
    updateData:firstData]
    build];

  NSData *secondData = [@"SOME NEW DATA" dataUsingEncoding:NSUTF8StringEncoding];

  writableLog = [[[[[[FBWritableLogBuilder builderWithWritableLog:writableLog]
    updateShortName:@"newshortname"]
    updateFileType:@"newfiletype"]
    updateHumanReadableName:@"newhuman"]
    updateData:secondData]
    build];

  XCTAssertEqualObjects(writableLog.shortName, @"newshortname");
  XCTAssertEqualObjects(writableLog.fileType, @"newfiletype");
  XCTAssertEqualObjects(writableLog.humanReadableName, @"newhuman");
  XCTAssertEqualObjects(writableLog.asData, secondData);
}

- (void)testBuilderReplacesStringsAndData
{
  NSData *firstData = [@"SOME DATA" dataUsingEncoding:NSUTF8StringEncoding];

  FBWritableLog *writableLog = [[[FBWritableLogBuilder builder]
    updateData:firstData]
    build];

  writableLog = [[[FBWritableLogBuilder builderWithWritableLog:writableLog]
    updateString:@"A String"]
    build];

  XCTAssertEqualObjects(writableLog.asData, [@"A String" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(writableLog.asString, @"A String");

  writableLog = [[[[FBWritableLogBuilder builderWithWritableLog:writableLog]
    updateString:@"Not me ever"]
    updateData:[@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]]
    build];

  XCTAssertEqualObjects(writableLog.asData, [@"I am now over here" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(writableLog.asString, @"I am now over here");
}

- (void)testStringAccessorReadsFromFile
{
  NSString *logString = @"FOO BAR BAZ";
  NSString *logPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"testBuilderReadsFromFile"] stringByAppendingPathExtension:@"txt"];
  [logString writeToFile:logString atomically:YES encoding:NSUTF8StringEncoding error:nil];

  FBWritableLog *writableLog = [[[FBWritableLogBuilder builder]
    updatePath:logPath]
    build];

  XCTAssertEqualObjects(writableLog.asString, writableLog.asString);
}

- (void)testReadingPathWritesToFile
{
  NSString *logString = @"FOO BAR BAZ";

  FBWritableLog *writableLog = [[[[FBWritableLogBuilder builder]
    updateString:logString]
    updateShortName:@"ballooon"]
    build];

  NSString *writeOutString = [NSString stringWithContentsOfFile:writableLog.asPath usedEncoding:nil error:nil];

  XCTAssertEqualObjects(writeOutString, logString);
}

@end
