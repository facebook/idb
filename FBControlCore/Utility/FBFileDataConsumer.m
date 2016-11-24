// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileDataConsumer.h"

#import "FBRunLoopSpinner.h"
#import "FBControlCoreError.h"

static BOOL awaitHasConsumedEOF(id<FBFileDataConsumer> consumer, NSTimeInterval timeout, NSError **error)
{
  BOOL success = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return consumer.hasConsumedEOF;
  }];
  if (!success) {
    return [[FBControlCoreError
      describeFormat:@"Timeout waiting %f seconds for EOF", timeout]
      failBool:error];
  }
  return YES;
}

@interface FBLineFileDataConsumer ()

@property (nonatomic, strong, nullable, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, nullable, readwrite) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) void (^consumer)(NSString *);

@end

@implementation FBLineFileDataConsumer

+ (instancetype)lineReaderWithConsumer:(void (^)(NSString *))consumer
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBControlCore.LineConsumer", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithQueue:queue consumer:consumer];
}

+ (instancetype)lineReaderWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer
{
  return [[self alloc] initWithQueue:queue consumer:consumer];
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _consumer = consumer;
  _buffer = [NSMutableData data];

  return self;
}

- (void)consumeData:(NSData *)data
{
  NSAssert(self.hasConsumedEOF == NO, @"Cannot consume data when EOF has been consumed");
  @synchronized (self) {
    [self.buffer appendData:data];
    while (self.buffer.length != 0) {
      NSRange newlineRange = [self.buffer
        rangeOfData:[NSData dataWithBytes:"\n" length:1]
        options:0
        range:NSMakeRange(0, self.buffer.length)];
      if (newlineRange.length == 0) {
        break;
      }
      NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
      [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:"" length:0];
      NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
      void (^consumer)(NSString *) = self.consumer;
      dispatch_async(self.queue, ^{
        consumer(line);
      });
    }
  }
}

- (void)consumeEndOfFile
{
  NSAssert(self.hasConsumedEOF == NO, @"Cannot consume EOF when EOF has been consumed");
  @synchronized (self) {
    void (^consumer)(NSString *) = self.consumer;
    dispatch_queue_t queue = self.queue;
    NSData *buffer = self.buffer;

    if (buffer.length != 0) {
      NSString *line = [[NSString alloc] initWithData:buffer encoding:NSUTF8StringEncoding];
      dispatch_async(queue, ^{
        consumer(line);
        self.consumer = nil;
        self.queue = nil;
        self.buffer = nil;
      });
    }
  }
}

- (BOOL)hasConsumedEOF
{
  @synchronized (self) {
    return self.consumer == nil;
  }
}

- (BOOL)awaitEndOfFileWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return awaitHasConsumedEOF(self, timeout, error);
}

@end

@interface FBAccumilatingFileDataConsumer ()

@property (nonatomic, strong, nullable, readonly) NSMutableData *mutableData;
@property (nonatomic, copy, nullable, readonly) NSData *finalData;

@end

@implementation FBAccumilatingFileDataConsumer

- (instancetype)init
{
  return [self initWithMutableData:NSMutableData.data];
}

- (instancetype)initWithMutableData:(NSMutableData *)mutableData
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mutableData = mutableData;
  return self;
}

- (void)consumeData:(NSData *)data
{
  NSAssert(self.hasConsumedEOF == NO, @"Cannot consume data when EOF has been consumed");
  @synchronized (self) {
    [self.mutableData appendData:data];
  }
}

- (void)consumeEndOfFile
{
  NSAssert(self.hasConsumedEOF == NO, @"Cannot consume EOF when EOF has been consumed");
  @synchronized (self) {
    _finalData = [self.mutableData copy];
    _mutableData = nil;
  }
}

- (NSData *)data
{
  @synchronized (self) {
    return self.finalData ?: [self.mutableData copy];
  }
}

- (BOOL)hasConsumedEOF
{
  @synchronized (self) {
    return self.finalData != nil;
  }
}

- (BOOL)awaitEndOfFileWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return awaitHasConsumedEOF(self, timeout, error);
}

@end

@interface FBCompositeFileDataConsumer ()

@property (nonatomic, copy, readonly) NSArray<id<FBFileDataConsumer>> *consumers;

@end

@implementation FBCompositeFileDataConsumer

+ (instancetype)consumerWithConsumers:(NSArray<id<FBFileDataConsumer>> *)consumers
{
  return [[self alloc] initWithConsumers:consumers];
}

- (instancetype)initWithConsumers:(NSArray<id<FBFileDataConsumer>> *)consumers
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumers = consumers;
  return self;
}

- (void)consumeData:(NSData *)data
{
  for (id<FBFileDataConsumer> consumer in self.consumers) {
    [consumer consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  for (id<FBFileDataConsumer> consumer in self.consumers) {
    [consumer consumeEndOfFile];
  }
}

- (BOOL)hasConsumedEOF
{
  for (id<FBFileDataConsumer> consumer in self.consumers) {
    if (!consumer.hasConsumedEOF) {
      return NO;
    }
  }
  return YES;
}

- (BOOL)awaitEndOfFileWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return awaitHasConsumedEOF(self, timeout, error);
}

@end
