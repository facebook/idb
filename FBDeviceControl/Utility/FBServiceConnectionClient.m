/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBServiceConnectionClient.h"

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

@interface FBServiceConnectionClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) id<FBDataConsumer, FBDataConsumerLifecycle> writer;
@property (nonatomic, strong, readonly) FBFileReader *reader;

@end

@implementation FBServiceConnectionClient

#pragma mark Initializers

+ (FBFutureContext<FBServiceConnectionClient *> *)clientForServiceConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  id<FBDataConsumer, FBDataConsumerLifecycle> writer = [FBFileWriter asyncWriterWithFileDescriptor:connection.socket closeOnEndOfFile:NO error:&error];
  if (!writer) {
    return [FBFutureContext futureContextWithError:error];
  }
  id<FBNotifyingBuffer> outputBuffer = FBDataBuffer.notifyingBuffer;
  id<FBDataConsumer> output = [FBCompositeDataConsumer consumerWithConsumers:@[
    outputBuffer,
    [FBLoggingDataConsumer consumerWithLogger:[logger withName:@"RECV"]],
  ]];

  FBFileReader *reader = [FBFileReader readerWithFileDescriptor:connection.socket closeOnEndOfFile:NO consumer:output logger:nil];
  return [[[reader
    startReading]
    onQueue:queue map:^(id _) {
      return [[self alloc] initWithConnection:connection writer:writer reader:reader buffer:outputBuffer queue:queue logger:logger];
    }]
    onQueue:queue contextualTeardown:^(FBServiceConnectionClient *client, FBFutureState __) {
      return [client teardown];
    }];
}


- (instancetype)initWithConnection:(FBAMDServiceConnection *)connection writer:(id<FBDataConsumer, FBDataConsumerLifecycle>)writer reader:(FBFileReader *)reader buffer:(id<FBNotifyingBuffer>)buffer queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _writer = writer;
  _reader = reader;
  _buffer = buffer;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<NSData *> *)send:(NSData *)payload terminator:(NSData *)terminator
{
  [self sendRaw:payload];
  return [self.buffer consumeAndNotifyWhen:terminator];
}

- (void)sendRaw:(NSData *)payload
{
  [self.writer consumeData:payload];
}

#pragma mark Private

- (FBFuture<NSNull *> *)teardown
{
  [self.logger logFormat:@"Stopping reading of %@", self.connection];
  return [[[self.reader
    stopReading]
    onQueue:self.queue fmap:^(id _) {
      [self.logger logFormat:@"Stopped reading of %@, stopping writing", self.connection];
      [self.writer consumeEndOfFile];
      return self.writer.finishedConsuming;
    }]
    onQueue:self.queue map:^(id _) {
      [self.logger logFormat:@"Stopped writing %@", self.connection];
      return NSNull.null;
    }];
}

@end
