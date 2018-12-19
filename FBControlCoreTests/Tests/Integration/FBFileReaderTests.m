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

@interface FBFileReaderTests : XCTestCase <FBFileConsumer>

@property (atomic, assign, readwrite) BOOL didRecieveEOF;

@end

@implementation FBFileReaderTests

- (void)setUp
{
  self.didRecieveEOF = NO;
}

- (void)testConsumesData
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  id<FBAccumulatingLineBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  NSError *error = nil;
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

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
  success = [[reader stopReading] await:&error] != nil;
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testConsumesEOFAfterStoppedReading
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBFileReader *reader = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:self];
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  NSError *error = nil;
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertEqual(reader.state, FBFileReaderStateReading);
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write some data.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [pipe.fileHandleForWriting writeData:expected];

  // Stop reading, we may recieve the consumeEndOfFile on a different queue
  // This is fine as this call will block until the call has happened.
  // Also the assignment is atomic.
  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);

  // Confirm we got an eof
  XCTAssertTrue(self.didRecieveEOF);
}

- (void)testCanStopReadingBeforeEOFResolvesWhenPipeCloses
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  id<FBAccumulatingLineBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  NSError *error = nil;
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [pipe.fileHandleForWriting writeData:expected];
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    return [expected isEqualToData:consumer.data];
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];

  // Stop reading, it shouldn't matter that an EOF wasn't sent
  FBFuture<NSNumber *> *stopFuture = [reader stopReading];
  success = [stopFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);

  // Write EOF
  [pipe.fileHandleForWriting closeFile];
}

- (void)testPipeClosingBehindBackOfConsumer
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  id<FBAccumulatingLineBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileHandle:pipe.fileHandleForReading consumer:consumer];
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  NSError *error = nil;
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Write some data and confirm that it is as expected.
  NSData *expected = [@"Foo Bar Baz" dataUsingEncoding:NSUTF8StringEncoding];
  [pipe.fileHandleForWriting writeData:expected];
  [pipe.fileHandleForWriting closeFile];
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (id _, id __) {
    return [expected isEqualToData:consumer.data];
  }];
  XCTestExpectation *expectation = [self expectationForPredicate:predicate evaluatedWithObject:self handler:nil];
  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];

  // Stop reading, it shouldn't matter that an EOF wasn't sent
  FBFuture<NSNumber *> *stopFuture = [reader stopReading];
  success = [stopFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);
}

- (void)testReadsFromFilePath
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);


  // Stop Reading
  error = nil;
  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);
}

- (void)testReadingTwiceFails
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading.
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Fail when starting again.
  error = nil;
  success = [[reader startReading] await:&error] != nil;
  XCTAssertNotNil(error);
  XCTAssertFalse(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);
}

- (void)testStoppingTwiceFails
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Stop Reading
  error = nil;
  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);

  // Stop Reading
  error = nil;
  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNotNil(error);
  XCTAssertFalse(success);
  XCTAssertEqual(reader.state, FBFileReaderStateTerminatedNormally);
}

- (void)testConcurrentAttachmentIsProhibited
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_group_t group = dispatch_group_create();
  __block FBFuture<NSNull *> *firstAttempt = nil;
  __block FBFuture<NSNull *> *secondAttempt = nil;
  __block FBFuture<NSNull *> *thirdAttempt = nil;

  dispatch_group_async(group, concurrentQueue, ^{
    firstAttempt = [reader startReading];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    secondAttempt = [reader startReading];
  });
  dispatch_group_async(group, concurrentQueue, ^{
    thirdAttempt = [reader startReading];
  });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

  [firstAttempt await:nil];
  [secondAttempt await:nil];
  [thirdAttempt await:nil];
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

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

  XCTAssertEqual(successes, 1u);
}

#pragma mark FBFileConsumer Implementation

- (void)consumeData:(NSData *)data
{

}

- (void)consumeEndOfFile
{
  self.didRecieveEOF = YES;
}

@end
