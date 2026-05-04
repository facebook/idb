/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <XCTestBootstrap/FBExceptionInfo.h>

@interface FBExceptionInfoTests : XCTestCase
@end

@implementation FBExceptionInfoTests

#pragma mark - Initializer Behavioral Contracts

- (void)testConvenienceInit_DefaultsFileToNilAndLineToZero
{
  // The convenience initializer should produce an object where file is nil and line is 0,
  // which is behaviorally different from the full initializer with explicit values.
  FBExceptionInfo *fromConvenience = [[FBExceptionInfo alloc] initWithMessage:@"error"];
  FBExceptionInfo *fromFull = [[FBExceptionInfo alloc] initWithMessage:@"error" file:@"Test.m" line:10];

  // Convenience init defaults
  XCTAssertNil(fromConvenience.file, @"Convenience init must default file to nil");
  XCTAssertEqual(fromConvenience.line, 0UL, @"Convenience init must default line to 0");

  // Full init preserves explicit values
  XCTAssertNotNil(fromFull.file, @"Full init must preserve the provided file");
  XCTAssertGreaterThan(fromFull.line, 0UL, @"Full init must preserve the provided line");
}

#pragma mark - Description Formatting

- (void)testDescription_IncludesMessageFileAndLine
{
  FBExceptionInfo *info = [[FBExceptionInfo alloc] initWithMessage:@"assertion failed" file:@"MyTest.m" line:55];

  NSString *desc = [info description];

  XCTAssertTrue([desc containsString:@"assertion failed"], @"Description must include the exception message");
  XCTAssertTrue([desc containsString:@"MyTest.m"], @"Description must include the file path");
  XCTAssertTrue([desc containsString:@"55"], @"Description must include the line number");
}

- (void)testDescription_WithNilFile_StillProducesOutput
{
  FBExceptionInfo *info = [[FBExceptionInfo alloc] initWithMessage:@"crash"];

  NSString *desc = [info description];

  // When file is nil, description should still be a non-empty string containing the message
  XCTAssertTrue(desc.length > 0, @"Description must produce non-empty output even with nil file");
  XCTAssertTrue([desc containsString:@"crash"], @"Description must include the message even when file is nil");
  XCTAssertTrue([desc containsString:@"0"], @"Description must include line 0 from convenience init");
}

- (void)testDescription_DiffersBetweenInitializers
{
  // The two initializers should produce different description outputs when given different data
  FBExceptionInfo *withFile = [[FBExceptionInfo alloc] initWithMessage:@"fail" file:@"Source.m" line:42];
  FBExceptionInfo *withoutFile = [[FBExceptionInfo alloc] initWithMessage:@"fail"];

  NSString *descWithFile = [withFile description];
  NSString *descWithoutFile = [withoutFile description];

  // Both contain the message
  XCTAssertTrue([descWithFile containsString:@"fail"], @"Both descriptions must contain the message");
  XCTAssertTrue([descWithoutFile containsString:@"fail"], @"Both descriptions must contain the message");

  // But they differ because one has file info and the other doesn't
  XCTAssertNotEqualObjects(descWithFile, descWithoutFile,
                           @"Descriptions should differ when file/line information differs");
  XCTAssertTrue([descWithFile containsString:@"Source.m"],
                @"Description from full init must include the file name");
}

@end
