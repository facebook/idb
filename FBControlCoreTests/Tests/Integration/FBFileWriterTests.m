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

@interface FBFileWriterTests : XCTestCase

@end

@implementation FBFileWriterTests

- (void)testClosesFileHandle
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBFileWriter *writer = [FBFileWriter syncWriterWithFileHandle:pipe.fileHandleForWriting];

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [writer consumeData:expected];
  NSData *actual = [pipe.fileHandleForReading availableData];
  XCTAssertEqualObjects(expected, actual);

  // Close the handle, confirm it does not assert if more data arrives.
  [writer consumeEndOfFile];
  XCTAssertNoThrow([writer consumeData:expected]);

  // There should be no more data to consume.
  actual = [pipe.fileHandleForReading readDataToEndOfFile];
  XCTAssertEqual(actual.length, 0u);
}

- (void)testNonBlocking
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBFileWriter *writer = [FBFileWriter asyncWriterWithFileHandle:pipe.fileHandleForWriting];

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [writer consumeData:expected];

  NSData *actual = [pipe.fileHandleForReading availableData];
  XCTAssertEqualObjects(expected, actual);

  // Close the handle, confirm it does not assert if more data arrives.
  [writer consumeEndOfFile];
  XCTAssertNoThrow([writer consumeData:expected]);

  // There should be no more data to consume.
  actual = [pipe.fileHandleForReading readDataToEndOfFile];
  XCTAssertEqual(actual.length, 0u);
}

@end
