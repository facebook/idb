/*
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
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(consumer.data, [@"FOOBAR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
}

- (void)testLineBufferAccumulationWithCapacity
{
  id<FBAccumulatingBuffer> consumer = [FBDataBuffer accumulatingBufferWithCapacity:3];
  [consumer consumeData:[@"F" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"F"]);
  [consumer consumeData:[@"O" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"FO"]);
  [consumer consumeData:[@"O" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"FOO"]);

  [consumer consumeData:[@"B" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"OOB"]);

  [consumer consumeData:[@"AR" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"BAR"]);

  [consumer consumeData:[@"ALONGSTRINGBUTIWANTAHIT" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(consumer.lines, @[@"HIT"]);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(consumer.lines, @[@"HIT"]);
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
}

- (void)testLineBufferedConsumer
{
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer synchronousLineConsumerWithBlock:^(NSString *line) {
    [lines addObject:line];
  }];

  [consumer consumeData:[@"FOO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
}

- (void)testLineBufferedConsumerAsync
{
  dispatch_queue_t queue = dispatch_queue_create("testLineBufferedConsumerAsync", DISPATCH_QUEUE_SERIAL);
  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer asynchronousLineConsumerWithBlock:^(NSString *line) {
    dispatch_sync(queue, ^{ [lines addObject:line]; });
  }];

  [consumer consumeData:[@"FOO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];
  usleep(1000);
  dispatch_sync(queue, ^{ XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"])); });
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  dispatch_sync(queue, ^{ XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"])); });
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  dispatch_sync(queue, ^{ XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"])); });
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
}

- (void)testUnbufferedConsumer
{
  NSData *expected = [@"FOOBARBAZ" dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableData *actual = NSMutableData.data;
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *incremental) {
    [actual appendData:incremental];
  }];

  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  usleep(1000);
  XCTAssertEqualObjects(expected, actual);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(expected, actual);
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
  XCTAssertEqualObjects(expected, actual);
}

- (void)testUnbufferedConsumerAsync
{
  NSData *expected = [@"FOOBARBAZ" dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableData *actual = NSMutableData.data;
  id<FBDataConsumer, FBDataConsumerLifecycle> consumer = [FBBlockDataConsumer asynchronousDataConsumerWithBlock:^(NSData *incremental) {
    [actual appendData:incremental];
  }];

  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  usleep(1000);
  XCTAssertEqualObjects(expected, actual);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];
  XCTAssertEqualObjects(expected, actual);
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"NOPE" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
  XCTAssertEqualObjects(expected, actual);
}

- (void)testLineBufferConsumption
{
  id<FBConsumableBuffer> consumer = FBDataBuffer.consumableBuffer;
  [consumer consumeData:[@"FOO" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertNil(consumer.consumeLineData);
  XCTAssertNil(consumer.consumeLineString);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeLineString, @"FOOBAR");
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"BANG\nBAZ" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nHELLO\nHERE" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeCurrentString, @"BANG\nBAZ\nHELLO\nHERE");
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"GOODBYE" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nFOR\nNOW" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeCurrentData, [@"GOODBYE\nFOR\nNOW" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"ILIED" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"$$SOZ\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects([consumer consumeUntil:[@"$$" dataUsingEncoding:NSUTF8StringEncoding]], [@"ILIED" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects(consumer.consumeLineString, @"SOZ");
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeData:[@"BACKAGAIN" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"\nTHIS\nIS\nTHE\nTAIL" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumer.consumeLineData, [@"BACKAGAIN" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertFalse(consumer.finishedConsuming.hasCompleted);

  [consumer consumeEndOfFile];

  XCTAssertTrue(consumer.finishedConsuming.hasCompleted);
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
  XCTAssertFalse(composite.finishedConsuming.hasCompleted);

  [composite consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];

  XCTAssertEqualObjects(consumable.consumeLineString, @"FOOBAR");
  XCTAssertNil(consumable.consumeLineString);
  XCTAssertFalse(consumable.finishedConsuming.hasCompleted);
  XCTAssertFalse(accumilating.finishedConsuming.hasCompleted);
  XCTAssertFalse(composite.finishedConsuming.hasCompleted);

  [composite consumeEndOfFile];
  XCTAssertTrue(consumable.finishedConsuming.hasCompleted);
  XCTAssertTrue(accumilating.finishedConsuming.hasCompleted);
  XCTAssertTrue(composite.finishedConsuming.hasCompleted);
}

- (void)testLengthBasedConsumption
{
  id<FBConsumableBuffer> consumer = FBDataBuffer.consumableBuffer;

  [consumer consumeData:[@"FOOBARRBAZZZ" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeEndOfFile];

  XCTAssertEqualObjects([consumer consumeLength:3], [@"FOO" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects([consumer consumeLength:4], [@"BARR" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertEqualObjects([consumer consumeLength:5], [@"BAZZZ" dataUsingEncoding:NSUTF8StringEncoding]);
  XCTAssertNil([consumer consumeLength:4]);
  XCTAssertEqualObjects([consumer consumeCurrentData], NSData.data);
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

- (void)testHeaderConsumption
{
  id<FBNotifyingBuffer> consumer = FBDataBuffer.notifyingBuffer;
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  XCTestExpectation *doneExpectation = [[XCTestExpectation alloc] initWithDescription:@"Resolved All"];

  NSData *payloadData = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger payloadLength = payloadData.length;
  NSData *headerData = [[NSData alloc] initWithBytes:&payloadLength length:sizeof(NSUInteger)];

  [[consumer
    consumeHeaderLength:sizeof(NSUInteger) derivedLength:^(NSData *data) {
      XCTAssertEqual(data.length, sizeof(NSUInteger));
      NSUInteger readPayloadLength = 0;
      [data getBytes:&readPayloadLength length:sizeof(NSUInteger)];
      XCTAssertEqual(readPayloadLength, payloadLength);
      return readPayloadLength;
    }]
    onQueue:queue doOnResolved:^(NSData *result) {
      XCTAssertEqualObjects(result, payloadData);
      [doneExpectation fulfill];
    }];

  [consumer consumeData:headerData];
  [consumer consumeData:payloadData];
  [consumer consumeEndOfFile];

  [self waitForExpectations:@[doneExpectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

@end
