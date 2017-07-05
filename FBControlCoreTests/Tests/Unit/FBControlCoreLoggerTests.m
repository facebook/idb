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

@interface FBControlCoreLoggerTests : XCTestCase

@end

@implementation FBControlCoreLoggerTests

- (void)testLoggingToFileDescriptor
{
  NSString *filename = [NSString stringWithFormat:@"%@.log", NSUUID.UUID.UUIDString];
  NSString *temporaryFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
  [[NSFileManager defaultManager] createFileAtPath:temporaryFilePath contents:nil attributes:nil];
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:temporaryFilePath];

  id<FBControlCoreLogger> logger = [FBControlCoreLogger systemLoggerWritingToFileDescriptor:fileHandle.fileDescriptor withDebugLogging:YES];
  [logger log:@"Some content"];
  [fileHandle synchronizeFile];
  [fileHandle closeFile];

  NSError *error;
  NSString *fileContent = [NSString stringWithContentsOfFile:temporaryFilePath encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([fileContent hasSuffix:@"Some content\n"], @"Unexpected fileContent: %@", fileContent);
}

@end
