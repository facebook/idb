/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToFileDescriptor:fileHandle.fileDescriptor closeOnEndOfFile:NO];
  [logger log:@"Some content"];
  [fileHandle synchronizeFile];
  [fileHandle closeFile];

  NSError *error;
  NSString *fileContent = [NSString stringWithContentsOfFile:temporaryFilePath encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  XCTAssertTrue([fileContent hasSuffix:@"Some content\n"], @"Unexpected fileContent: %@", fileContent);
}

- (void)testLoggingToConsumer
{
  id<FBConsumableBuffer> consumer = FBDataBuffer.consumableBuffer;
  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:consumer];

  [logger log:@"HELLO"];
  [logger log:@"WORLD"];

  XCTAssertEqualObjects(consumer.consumeLineString, @"HELLO");
  XCTAssertEqualObjects(consumer.consumeLineString, @"WORLD");

  logger = [logger withName:@"foo"];

  [logger log:@"HELLO"];
  [logger log:@"WORLD"];

  XCTAssertEqualObjects(consumer.consumeLineString, @"[foo] HELLO");
  XCTAssertEqualObjects(consumer.consumeLineString, @"[foo] WORLD");
}

- (void)testThreadSafetyOfConsumableLogger
{
  id<FBConsumableBuffer> consumer = FBDataBuffer.consumableBuffer;
  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:consumer];

  dispatch_group_t group = dispatch_group_create();
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_group_async(group, queue, ^{
    [logger log:@"1"];
  });
  dispatch_group_async(group, queue, ^{
    [logger log:@"2"];
  });
  dispatch_group_async(group, queue, ^{
    [logger log:@"3"];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  NSSet<NSString *> *expected = [NSSet setWithArray:@[@"1", @"2", @"3", @""]];
  NSSet<NSString *> *actual = [NSSet setWithArray:consumer.lines];

  XCTAssertEqualObjects(expected, actual);
}

@end
