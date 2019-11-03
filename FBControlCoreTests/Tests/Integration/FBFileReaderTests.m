/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import <sys/types.h>
#import <sys/stat.h>

@interface FBFileReaderTests : XCTestCase <FBDataConsumer>

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
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:pipe.fileHandleForReading.fileDescriptor closeOnEndOfFile:NO consumer:consumer logger:nil];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @0);
  XCTAssertEqualObjects(reader.finishedReading.result, @0);
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingNormally);
}

- (void)testConsumesEOFAfterStoppedReading
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:pipe.fileHandleForReading.fileDescriptor closeOnEndOfFile:NO consumer:self logger:nil];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(ECANCELED));
  XCTAssertEqualObjects(reader.finishedReading.result, @(ECANCELED));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);

  // Confirm we got an eof
  XCTAssertTrue(self.didRecieveEOF);
}

- (void)testConsumesEOFAfterStoppedReadingEvenIfOtherEndOfFifoDoesNotClose
{
  NSString *fifoPath = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  int status = mkfifo(fifoPath.UTF8String, S_IWUSR | S_IRUSR);
  XCTAssertEqual(status, 0);

  NSError *error = nil;
  NSArray<id> *writerAndReader = [[FBFuture
    futureWithFutures:@[
      [FBFileWriter asyncWriterForFilePath:fifoPath],
      [FBFileReader readerWithFilePath:fifoPath consumer:self logger:nil],
    ]]
    await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(writerAndReader);

  id<FBDataConsumer> writer = writerAndReader[0];
  FBFileReader *reader = writerAndReader[1];

  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write some data
  [writer consumeData:[@"HELLO\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [writer consumeData:[@"THERE\n" dataUsingEncoding:NSUTF8StringEncoding]];
  [writer consumeEndOfFile];

  success = [[reader stopReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Confirm we got an eof
  XCTAssertTrue(self.didRecieveEOF);
}

- (void)testCanStopReadingBeforeEOFResolvesWhenPipeCloses
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:pipe.fileHandleForReading.fileDescriptor closeOnEndOfFile:NO consumer:consumer logger:nil];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(ECANCELED));
  XCTAssertEqualObjects(reader.finishedReading.result, @(ECANCELED));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);

  // Write EOF
  [pipe.fileHandleForWriting closeFile];
}

- (void)testPipeClosingBehindBackOfConsumer
{
  // Setup
  NSPipe *pipe = NSPipe.pipe;
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:pipe.fileHandleForReading.fileDescriptor closeOnEndOfFile:NO consumer:consumer logger:nil];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @0);
  XCTAssertEqualObjects(reader.finishedReading.result, @0);
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingNormally);
}

- (void)testReadsFromFilePath
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self logger:nil] await:&error];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(ECANCELED));
  XCTAssertEqualObjects(reader.finishedReading.result, @(ECANCELED));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);
}

- (void)testReadingTwiceFails
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self logger:nil] await:&error];
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
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Cancellation should work.
  error = nil;
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(ECANCELED));
  XCTAssertEqualObjects(reader.finishedReading.result, @(ECANCELED));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);
}

- (void)testStoppingTwiceDoesNotError
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self logger:nil] await:&error];
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
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);
  XCTAssertEqualObjects(result, @(ECANCELED));

  // Stop Reading
  error = nil;
  result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(ECANCELED));
  XCTAssertEqualObjects(reader.finishedReading.result, @(ECANCELED));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);
}

- (void)testCancellationOnFinishedReading
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self logger:nil] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(reader);
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(reader.state, FBFileReaderStateReading);

  // Stop Reading
  FBFuture<NSNumber *> *finished = reader.finishedReading;
  XCTAssertEqual(finished.state, FBFutureStateRunning);
  success = [[finished cancel] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(finished.state, FBFutureStateCancelled);
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingByCancellation);
}

- (void)testConcurrentAttachmentIsProhibited
{
  // Read some data.
  NSError *error = nil;
  FBFileReader *reader = [[FBFileReader readerWithFilePath:@"/dev/urandom" consumer:self logger:nil] await:&error];
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

- (void)testAttemptingToReadAGarbageFileDescriptor
{
  // Setup
  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:92123 closeOnEndOfFile:NO consumer:self logger:nil];
  XCTAssertEqual(reader.state, FBFileReaderStateNotStarted);

  // Start reading, the start is asyncrhonous, so we can't know ahead of time if the fd is bad.
  NSError *error = nil;
  BOOL success = [[reader startReading] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  // Write some data and confirm that it is as expected.
  NSNumber *result = [[reader stopReading] await:&error];
  XCTAssertNil(error);
  XCTAssertEqualObjects(result, @(EBADF));
  XCTAssertEqualObjects(reader.finishedReading.result, @(EBADF));
  XCTAssertEqual(reader.state, FBFileReaderStateFinishedReadingInError);
}

#pragma mark FBDataConsumer Implementation

- (void)consumeEndOfFile
{
  self.didRecieveEOF = YES;
}

- (void)consumeData:(NSData *)data
{
}

@end
