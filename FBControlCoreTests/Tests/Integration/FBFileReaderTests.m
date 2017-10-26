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

@interface FBFileReaderTests : XCTestCase

@end

@implementation FBFileReaderTests

- (void)testConsumesData
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
  FBFileReader *writer = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];

  // Start reading
  NSError *error = nil;
  BOOL success = [[writer startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [pipe.fileHandleForWriting writeData:expected];
  [pipe.fileHandleForWriting closeFile];
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    return [expected isEqualToData:consumer.data];
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];

  // Stop reading
  success = [[writer stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testCanStopReadingBeforeEOFResolvesWhenPipeCloses
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
  FBFileReader *writer = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];

  // Start reading
  NSError *error = nil;
  BOOL success = [writer startReadingWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [pipe.fileHandleForWriting writeData:expected];
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    return [expected isEqualToData:consumer.data];
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];

  // Stop reading, it shouldn't matter that an EOF wasn't sent
  FBFuture<NSNull *> *stopFuture = [writer stopReading];
  success = [stopFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write EOF
  [pipe.fileHandleForWriting closeFile];
}

@end
