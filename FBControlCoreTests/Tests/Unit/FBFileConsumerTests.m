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

@interface FBFileConsumerTests : XCTestCase

@end

@implementation FBFileConsumerTests

- (void)testAccumilatingReader
{
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
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
  FBLineFileConsumer *consumer = [FBLineFileConsumer synchronousReaderWithConsumer:^(NSString *line) {
    [lines addObject:line];
  }];

  XCTAssertFalse(consumer.eofHasBeenReceived.hasCompleted);
  [consumer consumeData:[@"FOO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [consumer consumeData:[@"BAR\n" dataUsingEncoding:NSUTF8StringEncoding]];
  XCTAssertEqualObjects(lines, (@[@"FOO", @"BAR"]));
  [consumer consumeEndOfFile];
  XCTAssertTrue(consumer.eofHasBeenReceived.hasCompleted);
}

@end
