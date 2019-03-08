/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDataBuffer.h"

#import "FBControlCoreError.h"

@interface FBDataBuffer_Accumilating : NSObject <FBDataConsumer, FBAccumulatingBuffer>

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@implementation FBDataBuffer_Accumilating

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithBackingBuffer:NSMutableData.new];
}

- (instancetype)initWithBackingBuffer:(NSMutableData *)buffer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _buffer = buffer;
  _eofHasBeenReceivedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  @synchronized (self) {
    return [NSString stringWithFormat:@"Accumilating Buffer %lu Bytes", self.data.length];
  }
}

#pragma mark FBAccumilatingLineBuffer

- (NSData *)data
{
  @synchronized (self) {
    return [self.buffer copy];
  }
}

- (NSArray<NSString *> *)lines
{
  NSString *output = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
  return [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized (self) {
    NSAssert(self.eofHasBeenReceived.hasCompleted == NO, @"Cannot consume data after eof recieved");
    [self.buffer appendData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized (self) {
    NSAssert(self.eofHasBeenReceived.hasCompleted == NO, @"Cannot consume eof after eof recieved");
    [self.eofHasBeenReceivedFuture resolveWithResult:NSNull.null];
  }
}

#pragma mark FBDataConsumerLifecycle

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedFuture;
}

@end

@interface FBDataBuffer_Consumable_Forwarder : NSObject

@property (nonatomic, copy, readonly) NSData *terminal;
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;
@property (nonatomic, strong, nullable, readonly) dispatch_queue_t queue;

@end

@implementation FBDataBuffer_Consumable_Forwarder

- (instancetype)initWithTerminal:(NSData *)terminal consumer:(id<FBDataConsumer>)consumer queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _terminal = terminal;
  _consumer = consumer;
  _queue = queue;

  return self;
}

@end

@interface FBDataBuffer_Consumable : FBDataBuffer_Accumilating <FBConsumableBuffer>

@property (nonatomic, strong, nullable, readwrite) FBDataBuffer_Consumable_Forwarder *forwarder;

@end

@implementation FBDataBuffer_Consumable

#pragma mark Initializers

- (instancetype)initWithForwarder:(FBDataBuffer_Consumable_Forwarder *)forwarder;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _forwarder = forwarder;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  @synchronized (self) {
    return [NSString stringWithFormat:@"Consumable Buffer %lu Bytes", self.data.length];
  }
}

#pragma mark FBConsumableBuffer

- (nullable NSData *)consumeCurrentData
{
  @synchronized (self) {
    NSData *data = self.data;
    self.buffer.data = NSData.data;
    return data;
  }
}

- (nullable NSString *)consumeCurrentString
{
  NSData *data = [self consumeCurrentData];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (nullable NSData *)consumeUntil:(NSData *)terminal
{
  if (self.buffer.length == 0) {
    return nil;
  }
  NSRange newlineRange = [self.buffer rangeOfData:terminal options:0 range:NSMakeRange(0, self.buffer.length)];
  if (newlineRange.location == NSNotFound) {
    return nil;
  }
  NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
  [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + terminal.length) withBytes:"" length:0];
  return lineData;
}

- (nullable NSData *)consumeLineData
{
  return [self consumeUntil:FBDataBuffer.newlineTerminal];
}

- (nullable NSString *)consumeLineString
{
  NSData *lineData = self.consumeLineData;
  if (!lineData) {
    return nil;
  }
  return [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
}

- (BOOL)consume:(id<FBDataConsumer>)consumer untilTerminal:(NSData *)terminal error:(NSError **)error
{
  return [self consume:consumer onQueue:nil untilTerminal:terminal error:error];
}

- (BOOL)consume:(id<FBDataConsumer>)consumer onQueue:(dispatch_queue_t)queue untilTerminal:(NSData *)terminal error:(NSError **)error
{
  @synchronized (self) {
    if (self.forwarder) {
      return [[FBControlCoreError
        describe:@"Cannot listen for the two terminals at the same time"]
        failBool:error];
    }
    self.forwarder = [[FBDataBuffer_Consumable_Forwarder alloc] initWithTerminal:terminal consumer:consumer queue:queue];
    [self runForwarder];
  }
  return YES;
}

- (nullable id<FBDataConsumer>)removeForwardingConsumer
{
  FBDataBuffer_Consumable_Forwarder *forwarder = self.forwarder;
  self.forwarder = nil;
  return forwarder.consumer;
}

- (FBFuture<NSData *> *)consumeAndNotifyWhen:(NSData *)terminal
{
  FBMutableFuture<NSData *> *future = FBMutableFuture.future;
  id<FBDataConsumer> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    [self removeForwardingConsumer];
    [future resolveWithResult:data];
  }];

  NSError *error = nil;
  BOOL success = [self consume:consumer untilTerminal:terminal error:&error];
  if (!success) {
    return [FBFuture futureWithError:error];
  }
  [self runForwarder];
  return future;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [super consumeData:data];
  @synchronized (self) {
    [self runForwarder];
  }
}

#pragma mark Private

- (void)runForwarder
{
  FBDataBuffer_Consumable_Forwarder *forwarder = self.forwarder;
  if (!forwarder) {
    return;
  }
  NSData *partial = [self consumeUntil:forwarder.terminal];
  dispatch_queue_t queue = forwarder.queue;
  id<FBDataConsumer> consumer = forwarder.consumer;
  while (partial) {
    if (queue) {
      dispatch_async(queue, ^{
        [consumer consumeData:partial];
      });
    } else {
      [consumer consumeData:partial];
    }
    partial = [self consumeUntil:forwarder.terminal];
  }
}

@end

@implementation FBDataBuffer

#pragma mark Initializers

+ (id<FBAccumulatingBuffer>)accumulatingBuffer
{
  return [FBDataBuffer_Accumilating new];
}

+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data
{
  return [[FBDataBuffer_Accumilating alloc] initWithBackingBuffer:data];
}

+ (id<FBConsumableBuffer>)consumableBuffer
{
  return [self consumableBufferForwardingToConsumer:nil onQueue:nil terminal:nil];
}

+ (id<FBConsumableBuffer>)consumableBufferForwardingToConsumer:(id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue terminal:(NSData *)terminal
{
  FBDataBuffer_Consumable_Forwarder *forwarder = nil;
  if (consumer) {
    forwarder = [[FBDataBuffer_Consumable_Forwarder alloc] initWithTerminal:terminal consumer:consumer queue:queue];
  }
  return [[FBDataBuffer_Consumable alloc] initWithForwarder:forwarder];
}

+ (NSData *)newlineTerminal
{
  static dispatch_once_t onceToken;
  static NSData *data = nil;
  dispatch_once(&onceToken, ^{
    data = [NSData dataWithBytes:"\n" length:1];
  });
  return data;
}

@end
