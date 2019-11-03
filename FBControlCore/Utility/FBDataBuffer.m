/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDataBuffer.h"

#import "FBControlCoreError.h"

@interface FBDataBuffer_Accumilating : NSObject <FBDataConsumer, FBAccumulatingBuffer>

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, assign, readonly) size_t capacity;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *finishedConsumingFuture;

@end

@implementation FBDataBuffer_Accumilating

#pragma mark Initializers

- (instancetype)init
{
  return [self initWithBackingBuffer:NSMutableData.new capacity:0];
}

- (instancetype)initWithBackingBuffer:(NSMutableData *)buffer capacity:(size_t)capacity
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _buffer = buffer;
  _capacity = capacity;
  _finishedConsumingFuture = FBMutableFuture.future;

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
    if (self.finishedConsuming.hasCompleted) {
      return;
    }
    [self.buffer appendData:data];
    if (self.capacity > 0) {
      NSInteger overrun = (NSInteger) self.buffer.length - (NSInteger) self.capacity;
      if (overrun > 0) {
        [self.buffer replaceBytesInRange:NSMakeRange(0, (NSUInteger) overrun) withBytes:NULL length:0];
      }
    }
  }
}

- (void)consumeEndOfFile
{
  @synchronized (self) {
    if (self.finishedConsuming.hasCompleted) {
      return;
    }
    [self.finishedConsumingFuture resolveWithResult:NSNull.null];
  }
}

#pragma mark FBDataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingFuture;
}

@end

@protocol FBDataBuffer_Forwarder <NSObject>

- (void)run:(id<FBConsumableBuffer>)buffer;

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

@end

@interface FBDataBuffer_Terminal_Forwarder : NSObject <FBDataBuffer_Forwarder>

@property (nonatomic, copy, readonly) NSData *terminal;
@property (nonatomic, strong, nullable, readonly) dispatch_queue_t queue;

@end

@implementation FBDataBuffer_Terminal_Forwarder

@synthesize consumer = _consumer;

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

- (void)run:(id<FBConsumableBuffer>)buffer
{
  NSData *partial = [buffer consumeUntil:self.terminal];
  dispatch_queue_t queue = self.queue;
  id<FBDataConsumer> consumer = self.consumer;
  while (partial) {
    if (queue) {
      dispatch_async(queue, ^{
        [consumer consumeData:partial];
      });
    } else {
      [consumer consumeData:partial];
    }
    partial = [buffer consumeUntil:self.terminal];
  }
}

@end

@interface FBDataBuffer_Header_Forwarder : NSObject <FBDataBuffer_Forwarder>

@property (nonatomic, assign, readonly) NSUInteger headerLength;
@property (nonatomic, strong, readonly) NSUInteger(^derivedLength)(NSData *);
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) NSNumber *knownderivedLength;

@end

@implementation FBDataBuffer_Header_Forwarder

@synthesize consumer = _consumer;

- (instancetype)initWithHeaderLength:(NSUInteger)headerLength derivedLength:(NSUInteger(^)(NSData *))derivedLength consumer:(id<FBDataConsumer>)consumer queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _headerLength = headerLength;
  _derivedLength = derivedLength;
  _consumer = consumer;
  _queue = queue;

  return self;
}

- (void)run:(id<FBConsumableBuffer>)buffer
{
  if (!self.knownderivedLength) {
    NSData *header = [buffer consumeLength:self.headerLength];
    if (!header) {
      return;
    }
    self.knownderivedLength = @(self.derivedLength(header));
  }
  NSData *data = [buffer consumeLength:self.knownderivedLength.unsignedIntegerValue];
  dispatch_queue_t queue = self.queue;
  id<FBDataConsumer> consumer = self.consumer;
  if (data) {
    if (queue) {
      dispatch_async(queue, ^{
        [consumer consumeData:data];
      });
    } else {
      [consumer consumeData:data];
    }
  }
}

@end

@interface FBDataBuffer_Consumable : FBDataBuffer_Accumilating <FBConsumableBuffer, FBNotifyingBuffer>

@property (nonatomic, strong, nullable, readwrite) id<FBDataBuffer_Forwarder> forwarder;

@end

@implementation FBDataBuffer_Consumable

#pragma mark Initializers

- (instancetype)initWithForwarder:(FBDataBuffer_Terminal_Forwarder *)forwarder;
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

- (nullable NSData *)consumeLength:(NSUInteger)length
{
  @synchronized (self) {
    if (length > self.buffer.length) {
      return nil;
    }
    NSRange range = NSMakeRange(0, length);
    NSData *data = [self.buffer subdataWithRange:range];
    if (!data) {
      return nil;
    }
    [self.buffer replaceBytesInRange:range withBytes:"" length:0];
    return data;
  }
}

- (nullable NSData *)consumeUntil:(NSData *)terminal
{
  @synchronized (self) {
    if (self.buffer.length == 0) {
      return nil;
    }
    NSRange terminalRange = [self.buffer rangeOfData:terminal options:0 range:NSMakeRange(0, self.buffer.length)];
    if (terminalRange.location == NSNotFound) {
      return nil;
    }
    NSData *data = [self.buffer subdataWithRange:NSMakeRange(0, terminalRange.location)];
    [self.buffer replaceBytesInRange:NSMakeRange(0, terminalRange.location + terminal.length) withBytes:"" length:0];
    return data;
  }
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

- (BOOL)consume:(id<FBDataConsumer>)consumer onQueue:(dispatch_queue_t)queue untilTerminal:(NSData *)terminal error:(NSError **)error
{
  id<FBDataBuffer_Forwarder> forwarder = [[FBDataBuffer_Terminal_Forwarder alloc] initWithTerminal:terminal consumer:consumer queue:queue];
  return [self attachForwardingConsumer:forwarder error:error];
}

- (FBFuture<NSData *> *)consumeAndNotifyWhen:(NSData *)terminal
{
  FBMutableFuture<NSData *> *future = FBMutableFuture.future;
  id<FBDataConsumer> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    [self removeForwardingConsumer];
    [future resolveWithResult:data];
  }];

  NSError *error = nil;
  if (![self consume:consumer untilTerminal:terminal error:&error]) {
    return [FBFuture futureWithError:error];
  }
  return future;
}

- (FBFuture<NSData *> *)consumeHeaderLength:(NSUInteger)headerLength derivedLength:(NSUInteger(^)(NSData *))derivedLength
{
  FBMutableFuture<NSData *> *future = FBMutableFuture.future;
  id<FBDataConsumer> consumer = [FBBlockDataConsumer synchronousDataConsumerWithBlock:^(NSData *data) {
    [self removeForwardingConsumer];
    [future resolveWithResult:data];
  }];

  id<FBDataBuffer_Forwarder> forwarder = [[FBDataBuffer_Header_Forwarder alloc] initWithHeaderLength:headerLength derivedLength:derivedLength consumer:consumer queue:nil];
  NSError *error = nil;
  if (![self attachForwardingConsumer:forwarder error:&error]) {
    return [FBFuture futureWithError:error];
  }
  return future;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [super consumeData:data];
  @synchronized (self) {
    [self.forwarder run:self];
  }
}

#pragma mark Private

- (BOOL)attachForwardingConsumer:(id<FBDataBuffer_Forwarder>)forwarder error:(NSError **)error
{
  @synchronized (self) {
    if (self.forwarder) {
      return [[FBControlCoreError
        describe:@"Cannot listen for the two terminals at the same time"]
        failBool:error];
    }
    self.forwarder = forwarder;
    [self.forwarder run:self];
  }
  return YES;
}

- (nullable id<FBDataConsumer>)removeForwardingConsumer
{
  id<FBDataBuffer_Forwarder> forwarder = self.forwarder;
  self.forwarder = nil;
  return forwarder.consumer;
}

- (BOOL)consume:(id<FBDataConsumer>)consumer untilTerminal:(NSData *)terminal error:(NSError **)error
{
  return [self consume:consumer onQueue:nil untilTerminal:terminal error:error];
}

@end

@implementation FBDataBuffer

#pragma mark Initializers

+ (id<FBAccumulatingBuffer>)accumulatingBuffer
{
  return [FBDataBuffer_Accumilating new];
}

+ (id<FBAccumulatingBuffer>)accumulatingBufferWithCapacity:(size_t)capacity
{
  NSParameterAssert(capacity > 0);
  return [[FBDataBuffer_Accumilating alloc] initWithBackingBuffer:NSMutableData.data capacity:capacity];
}

+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data
{
  return [[FBDataBuffer_Accumilating alloc] initWithBackingBuffer:data capacity:0];
}

+ (id<FBConsumableBuffer>)consumableBuffer
{
  return [self consumableBufferForwardingToConsumer:nil onQueue:nil terminal:nil];
}

+ (id<FBNotifyingBuffer>)notifyingBuffer
{
  return [self consumableBufferForwardingToConsumer:nil onQueue:nil terminal:nil];
}

+ (id<FBNotifyingBuffer>)consumableBufferForwardingToConsumer:(id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue terminal:(NSData *)terminal
{
  FBDataBuffer_Terminal_Forwarder *forwarder = nil;
  if (consumer) {
    forwarder = [[FBDataBuffer_Terminal_Forwarder alloc] initWithTerminal:terminal consumer:consumer queue:queue];
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
