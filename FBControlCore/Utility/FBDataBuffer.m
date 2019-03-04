/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDataBuffer.h"

#import "FBControlCoreError.h"

@interface FBDataBuffer_Accumilating : NSObject <FBDataConsumer, FBAccumulatingBuffer>

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@interface FBDataBuffer_Consumable : FBDataBuffer_Accumilating <FBConsumableBuffer>

@property (nonatomic, copy, nullable, readwrite) NSData *notificationTerminal;
@property (nonatomic, strong, nullable, readwrite) FBMutableFuture<NSData *> *notification;

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

+ (NSData *)newlineTerminal
{
  static dispatch_once_t onceToken;
  static NSData *data = nil;
  dispatch_once(&onceToken, ^{
    data = [NSData dataWithBytes:"\n" length:1];
  });
  return data;
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

@implementation FBDataBuffer_Consumable

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
  return [self consumeUntil:FBDataBuffer_Accumilating.newlineTerminal];
}

- (nullable NSString *)consumeLineString
{
  NSData *lineData = self.consumeLineData;
  if (!lineData) {
    return nil;
  }
  return [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
}

- (FBFuture<NSString *> *)consumeAndNotifyWhen:(NSData *)terminal
{
  @synchronized (self) {
    if (self.notificationTerminal) {
      return [[FBControlCoreError
        describe:@"Cannot listen for the two terminals at the same time"]
        failFuture];
    }
    NSData *partial = [self consumeUntil:terminal];
    if (partial) {
      return [FBFuture futureWithResult:partial];
    }
    self.notificationTerminal = terminal;
    self.notification = FBMutableFuture.future;
    return self.notification;
  }
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [super consumeData:data];
  @synchronized (self) {
    if (!self.notificationTerminal) {
      return;
    }
    NSData *partial = [self consumeUntil:self.notificationTerminal];
    if (!partial) {
      return;
    }
    [self.notification resolveWithResult:partial];
    self.notification = nil;
    self.notificationTerminal = nil;
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
  return [FBDataBuffer_Consumable new];
}

@end
