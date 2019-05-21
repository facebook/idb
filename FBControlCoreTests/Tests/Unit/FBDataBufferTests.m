/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBDataConsumerTests : XCTestCase

@end

@implementation FBDataConsumerTests

- (void)testLineBufferAccumulation
{
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.data, [@"FOOBAR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(consumer.data, [@"FOOBAR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

- (void)testLineBufferedConsumer
{
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer synchronousLineConsumerWithBlock:^(NSString *line) {
    [lines addObject:line];
  }];

  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);
  [consumer consumeData:[@"FOO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  [consumer consumeEndOfFile];
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

- (void)testUnbufferedConsumer
{
  NSMutableData *actual = NSMutableData.data;
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *incremental) {
    [actual appendData:incremental];
  }];

  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeEndOfFile];
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);

  NSData *expected = [@"FOOBARBAZ" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testLineBufferConsumption
{
  id<FBConsumableBuffer> consumer = FBDataBuffer.consumableBuffer;
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
  id<FBAccumulatingBuffer> accumilating =  FBDataBuffer.consumableBuffer;
  id<FBConsumableBuffer> consumable =  FBDataBuffer.consumableBuffer;
  id<FBDataConsumer, FBDataConsumerLifecycle> composite = [FBCompositeDataConsumer consumerWithConsumers:@[
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

- (void)testFutureTerminalConsumption
{
  id<FBNotifyingBuffer> consumer = FBDataBuffer.notifyingBuffer;
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
