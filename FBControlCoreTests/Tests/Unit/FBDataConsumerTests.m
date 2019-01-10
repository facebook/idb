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

@interface FBDataConsumerTests : XCTestCase

@end

@implementation FBDataConsumerTests

- (void)testLineBufferAccumulation
{
  id<FBAccumulatingBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.data, [@"FOOBAR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(consumer.data, [@"FOOBAR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

- (void)testLineConsumer
{
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  FBLineDataConsumer *consumer = [FBLineDataConsumer synchronousReaderWithConsumer:^(NSString *line) {
    [lines addObject:line];
  }];

  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);
  [consumer consumeData:[@"FOO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  [consumer consumeEndOfFile];
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

- (void)testLineBufferConsumption
{
  id<FBConsumableBuffer> consumer = FBLineBuffer.consumableBuffer;
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertNil(consumer.consumeLineData);
  XCTAssertNil(consumer.consumeLineString);
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeLineString, @"FOOBAR");
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeData:[@"BANG\nBAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nHELLO\nHERE" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeCurrentString, @"BANG\nBAZ\nHELLO\nHERE");
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeData:[@"GOODBYE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nFOR\nNOW" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeCurrentData, [@"GOODBYE\nFOR\nNOW" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeData:[@"ILIED" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"$$SOZ\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects([consumer consumeUntil:[@"$$" dataUsingEncoding:NSUTF8StringEncoding]], [@"ILIED" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(consumer.consumeLineString, @"SOZ");
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeData:[@"BACKAGAIN" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nTHIS\nIS\nTHE\nTAIL" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeLineData, [@"BACKAGAIN" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeEndOfFile];

  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
  XCTAssertEqualObjects(consumer.consumeLineString, @"THIS");
  XCTAssertEqualObjects(consumer.consumeLineData, [@"IS" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(consumer.consumeLineString, @"THE");
  XCTAssertNil(consumer.consumeLineString);
  XCTAssertEqualObjects(consumer.consumeCurrentString, @"TAIL");
}

- (void)testCompositeWithCompletion
{
  id<FBAccumulatingBuffer> accumilating =  FBLineBuffer.consumableBuffer;
  id<FBConsumableBuffer> consumable =  FBLineBuffer.consumableBuffer;
  id<FBDataConsumerLifecycle> composite = [FBCompositeDataConsumer consumerWithConsumers:@[
    accumilating,
    consumable,
  ]];

  [composite consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertNil(consumable.consumeLineString);
  XCTAssertFalse(composite.eofHasBeenReceived.hasCompleted);

  [composite consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumable.consumeLineString, @"FOOBAR");
  XCTAssertNil(consumable.consumeLineString);
  XCTAssertFalse(consumable.eofHasBeenReceived.hasCompleted);
  XCTAssertFalse(accumilating.eofHasBeenReceived.hasCompleted);
  XCTAssertFalse(composite.eofHasBeenReceived.hasCompleted);

  [composite consumeEndOfFile];
  XCTAssertTrue(consumable.eofHasBeenReceived.hasCompleted);
  XCTAssertTrue(accumilating.eofHasBeenReceived.hasCompleted);
  XCTAssertTrue(composite.eofHasBeenReceived.hasCompleted);
}

- (void)testFutureConsumption
{
  id<FBConsumableBuffer> consumer = [FBLineBuffer consumableBuffer];
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  XCTestExpectation *doneExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved All"];

  [[[consumer
    consumeAndNotifyWhen:[@"$$" dataUsingEncoding:NSUTF8StringEncoding]]
    onQueue:queue fmap:^(NSData *result) {
      XCTAssertEqualObjects(result, [@"FOO" dataUsingEncoding:NSUTF8StringEncoding]);
      return [consumer consumeAndNotifyWhen:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    }]
    onQueue:queue doOnResolved:^(NSData *result) {
      XCTAssertEqualObjects(result, [@"BAR" dataUsingEncoding:NSUTF8StringEncoding]);
      [doneExpectation fulfill];
    }];

  [consumer consumeData:[@"FOO$$BAR\nBAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeEndOfFile];

  [self waitForExpectations:@[doneExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}


@end
