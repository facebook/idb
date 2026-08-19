/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDServiceConnection.h>

static AMSecureIOContext NullSecureIOContext(CFTypeRef connection)
{
  return NULL;
}

static int32_t EndOfFileReceive(CFTypeRef connection, void *buffer, size_t bytes)
{
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

@end
