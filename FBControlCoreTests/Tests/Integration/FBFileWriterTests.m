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

#import <sys/types.h>
#import <sys/stat.h>

@interface FBFileWriterTests : XCTestCase

@end

@implementation FBFileWriterTests

- (void)testNonBlockingCloseOfPipe
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  NSError *error = nil;
  id<FBDataConsumer, FBDataConsumerLifecycle> writer = [FBFileWriter asyncWriterWithFileHandle:pipe.fileHandleForWriting error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(writer);

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [writer consumeData:expected];

  NSData *actual = [pipe.fileHandleForReading availableData];
  XCTAssertEqualObjects(expected, actual);

  // Close the writer by consuming the end of file
  [writer consumeEndOfFile];
  BOOL success = [writer.eofHasBeenReceived await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [pipe.fileHandleForWriting closeFile];
  [pipe.fileHandleForReading closeFile];
}

- (void)testNonBlockingClose
{
  // Setup
  NSError *error = nil;
  NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
  id<FBDataConsumer, FBDataConsumerLifecycle> writer = [FBFileWriter asyncWriterWithFileHandle:fileHandle error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(writer);

  // Write some data and confirm that it is as expected.
  NSData *data = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [writer consumeData:data];
  [writer consumeEndOfFile];
}

- (void)testOpeningAFifoAtBothEndsAsynchronously
{
  id<FBAccumulatingBuffer> consumer = [FBLineBuffer accumulatingBuffer];

  NSString *fifoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  int status = mkfifo(fifoPath.UTF8String, S_IWUSR | S_IRUSR);
  XCTAssertEqual(status, 0);

  FBFuture<NSArray<id> *> *futures = [FBFuture futureWithFutures:@[
    [FBFileWriter asyncWriterForFilePath:fifoPath],
    [FBFileReader readerWithFilePath:fifoPath consumer:consumer logger:nil],
  ]];

  NSError *error = nil;
  NSArray<id> *results = [futures await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(results);

  id<FBDataConsumer> writer = results[0];
  FBFileReader *reader = results[1];

  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [writer consumeData:[@"HELLO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [writer consumeData:[@"THERE\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [writer consumeEndOfFile];

  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  success = [consumer.eofHasBeenReceived await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
