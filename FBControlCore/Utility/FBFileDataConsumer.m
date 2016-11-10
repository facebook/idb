// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileDataConsumer.h"

@interface FBLineFileDataConsumer ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, readonly) void (^consumer)(NSString *);
@property (nonatomic, strong, readonly) NSMutableData *buffer;

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
      dispatch_async(self.queue, ^{
        self.consumer(line);
      });
    }
  }
}

- (void)consumeEndOfFile
{
  @synchronized (self) {
    if (self.buffer.length != 0) {
      NSString *line = [[NSString alloc] initWithData:self.buffer encoding:NSUTF8StringEncoding];
      dispatch_async(self.queue, ^{
        self.consumer(line);
      });
      self.buffer.data = [NSData data];
    }
  }
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
  @synchronized (self) {
    [self.mutableData appendData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized (self) {
    NSAssert(self.mutableData, @"Cannot consume EOF twice");

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

@end
