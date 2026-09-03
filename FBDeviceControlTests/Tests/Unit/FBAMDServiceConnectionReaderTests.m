/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl-Swift.h>

static AMSecureIOContext NullSecureIOContext(CFTypeRef connection)
{
  return NULL;
}

static int32_t EndOfFileReceive(CFTypeRef connection, void *buffer, size_t bytes)
{
  return 0;
}

// Gate for the blocking-receive fake: receive blocks until invalidation
// signals it, mimicking a socket read unblocked by connection invalidation.
static dispatch_semaphore_t sReceiveGate;

static int32_t BlockingReceive(CFTypeRef connection, void *buffer, size_t bytes)
{
  dispatch_semaphore_wait(sReceiveGate, DISPATCH_TIME_FOREVER);
  return 0;
}

static int InvalidateUnblockingReceive(CFTypeRef connection)
{
  dispatch_semaphore_signal(sReceiveGate);
  return 0;
}

@interface FBAMDServiceConnectionReaderTests : XCTestCase

@end

@implementation FBAMDServiceConnectionReaderTests

- (FBAMDServiceConnection *)connectionReceivingEndOfFile
{
  AMDCalls calls = {};
  calls.ServiceConnectionGetSecureIOContext = NullSecureIOContext;
  calls.ServiceConnectionReceive = EndOfFileReceive;
  return [FBAMDServiceConnection
          connectionWithName:@"test-connection"
          connection:(__bridge AMDServiceConnectionRef) @"fake-connection-ref"
          device:NULL
          calls:calls
          logger:FBControlCoreGlobalConfiguration.defaultLogger];
}

- (void)testReaderDeliversEndOfFileToTheConsumer
{
  FBAMDServiceConnection *connection = [self connectionReceivingEndOfFile];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.tests.reader", DISPATCH_QUEUE_SERIAL);
  id<FBFileReaderProtocol> reader = [connection readFromConnectionWritingToConsumer:consumer onQueue:queue];

  NSError *error = nil;
  XCTAssertNotNil([reader.startReading awaitWithTimeout:5 error:&error]);
  XCTAssertNotNil([consumer.finishedConsuming awaitWithTimeout:5 error:&error]);

  NSNumber *finished = [reader.finishedReading awaitWithTimeout:5 error:&error];
  XCTAssertEqualObjects(finished, @(FBFileReaderStateFinishedReadingNormally));
}

- (void)testInvalidationWaitsForInFlightReadToFinish
{
  sReceiveGate = dispatch_semaphore_create(0);
  AMDCalls calls = {};
  calls.ServiceConnectionGetSecureIOContext = NullSecureIOContext;
  calls.ServiceConnectionReceive = BlockingReceive;
  calls.ServiceConnectionInvalidate = InvalidateUnblockingReceive;
  FBAMDServiceConnection *connection = [FBAMDServiceConnection
                                        connectionWithName:@"test-connection"
                                        connection:(__bridge AMDServiceConnectionRef) @"fake-connection-ref"
                                        device:NULL
                                        calls:calls
                                        logger:FBControlCoreGlobalConfiguration.defaultLogger];
  id<FBAccumulatingBuffer> consumer = FBDataBuffer.accumulatingBuffer;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbdevicecontrol.tests.blocked-reader", DISPATCH_QUEUE_SERIAL);
  id<FBFileReaderProtocol> reader = [connection readFromConnectionWritingToConsumer:consumer onQueue:queue];

  NSError *error = nil;
  XCTAssertNotNil([reader.startReading awaitWithTimeout:5 error:&error]);

  // Invalidation unblocks the (gated) receive and must not return until the
  // read loop has exited.
  XCTAssertTrue([connection invalidateWithError:&error]);
  XCTAssertEqual(reader.finishedReading.state, FBFutureStateDone);
}

@end
