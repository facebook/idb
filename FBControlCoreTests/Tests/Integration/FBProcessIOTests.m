/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <sys/types.h>
#import <sys/stat.h>

@interface FBProcessIOTests : XCTestCase

@end

@implementation FBProcessIOTests

- (void)testDetachmentMultipleTimesIsPermitted
{
  id<FBDataConsumer, FBDataConsumerLifecycle> stdInConsumer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer, FBDataConsumerLifecycle> stdOutConsumer = FBDataBuffer.consumableBuffer;
  FBProcessIO *io = [[FBProcessIO alloc] initWithStdIn:nil stdOut:[FBProcessOutput outputForDataConsumer:stdInConsumer] stdErr:[FBProcessOutput outputForDataConsumer:stdOutConsumer]];

  NSError *error = nil;
  FBProcessIOAttachment *attachment = [[io attach] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(attachment);

  dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_group_t group = dispatch_group_create();
  __block FBFuture<NSNull *> *first;
  __block FBFuture<NSNull *> *second;
  __block FBFuture<NSNull *> *third;
  __block FBFuture<NSNull *> *fourth;

  dispatch_group_async(group, concurrentQueue, ^{
    first = [attachment detach];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    second = [attachment detach];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    third = [attachment detach];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    fourth = [attachment detach];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  for (FBFuture<NSNull *> *attempt in @[first, second, third, fourth]) {
    BOOL success = [attempt await:&error] != nil;
    XCTAssertNil(error);
    XCTAssertTrue(success);
    XCTAssertTrue(stdInConsumer.finishedConsuming.hasCompleted);
  }
}

- (void)testMultipleAttachmentIsNotPermitted
{
  id<FBDataConsumer, FBDataConsumerLifecycle> stdInConsumer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer, FBDataConsumerLifecycle> stdOutConsumer = FBDataBuffer.consumableBuffer;
  FBProcessIO *io = [[FBProcessIO alloc] initWithStdIn:nil stdOut:[FBProcessOutput outputForDataConsumer:stdInConsumer] stdErr:[FBProcessOutput outputForDataConsumer:stdOutConsumer]];

  NSError *error = nil;
  FBProcessIOAttachment *attachment = [[io attach] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(attachment);

  BOOL success = [[io attach] await:&error] != nil;
  XCTAssertNotNil(error);
  XCTAssertFalse(success);

  error = nil;
  success = [[attachment detach] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
