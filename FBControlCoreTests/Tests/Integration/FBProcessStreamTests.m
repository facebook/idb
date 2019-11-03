/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBProcessStreamTests : XCTestCase

@end

@implementation FBProcessStreamTests

- (void)testClosingActiveStreamStopsWriting
{
  id<FBConsumableBuffer> consumer = [FBDataBuffer consumableBuffer];

  FBProcessOutput *output = [FBProcessOutput outputForDataConsumer:consumer];
  NSError *error = nil;
  FBProcessStreamAttachment *attachment = [[output attach] await:&error];
  XCTAssertNil(error);
  XCTAssertTrue(attachment.fileDescriptor);
  XCTAssertEqual(attachment.mode, FBProcessStreamAttachmentModeOutput);

  NSData *data = [@"HELLO WORLD\n" dataUsingEncoding:NSUTF8StringEncoding];
  write(attachment.fileDescriptor, data.bytes, data.length);
  data = [@"HELLO AGAIN" dataUsingEncoding:NSUTF8StringEncoding];
  write(attachment.fileDescriptor, data.bytes, data.length);

  [[output detach] await:&error];
  XCTAssertNil(error);

  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
}

- (void)testViaFifo
{
  id<FBAccumulatingBuffer> buffer = [FBDataBuffer accumulatingBuffer];
  NSError *error = nil;
  id<FBProcessFileOutput> output = [[[FBProcessOutput outputForDataConsumer:buffer] providedThroughFile] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(output);

  // Start Reading Asyncly so that the fifo is opened, it can then be written to.
  FBFuture *startReading = [output startReading];
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:output.filePath];
  BOOL success = [startReading await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [fileHandle writeData:[@"HELLO WORLD\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [fileHandle writeData:[@"HELLO AGAIN" dataUsingEncoding:NSUTF8StringEncoding]];
  [fileHandle closeFile];

  success = [buffer.finishedConsuming await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSArray<NSString *> *expected = @[@"HELLO WORLD", @"HELLO AGAIN"];
  XCTAssertEqualObjects(buffer.lines, expected);
}

- (void)testFileToFileDoesNotInvolveIndirection
{
  NSString *filePath = @"/tmp/hello_world.txt";
  NSError *error = nil;
  id<FBProcessFileOutput> output = [[[FBProcessOutput outputForFilePath:filePath] providedThroughFile] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(output);

  XCTAssertEqualObjects(filePath, output.filePath);
}

- (void)testConcurrentAttachmentIsProhibited
{
  id<FBConsumableBuffer> consumer = [FBDataBuffer consumableBuffer];
  FBProcessOutput *output = [FBProcessOutput outputForDataConsumer:consumer];

  dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_group_t group = dispatch_group_create();
  __block FBFuture<FBProcessStreamAttachment *> *firstAttempt = nil;
  __block FBFuture<FBProcessStreamAttachment *> *secondAttempt = nil;
  __block FBFuture<FBProcessStreamAttachment *> *thirdAttempt = nil;

  dispatch_group_async(group, concurrentQueue, ^{
    firstAttempt = [output attach];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    secondAttempt = [output attach];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    thirdAttempt = [output attach];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  [firstAttempt await:nil];
  [secondAttempt await:nil];
  [thirdAttempt await:nil];

  NSUInteger successes = 0;
  if (firstAttempt.state == FBFutureStateDone) {
    successes++;
  }
  if (secondAttempt.state == FBFutureStateDone) {
    successes++;
  }
  if (thirdAttempt.state == FBFutureStateDone) {
    successes++;
  }

  NSError *error;
  BOOL success = [[output detach] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);
  XCTAssertEqual(successes, 1u);
}

@end
