// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileConsumer.h"

#import "NSRunLoop+FBControlCore.h"
#import "FBControlCoreError.h"
#import "FBLineBuffer.h"

@interface FBLineFileConsumer ()

@property (nonatomic, strong, nullable, readwrite) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) void (^consumer)(NSData *);
@property (nonatomic, strong, readwrite) FBLineBuffer *buffer;

@end

typedef void (^dataBlock)(NSData *);
static inline dataBlock FBDataConsumerBlock (void(^consumer)(NSString *)) {
  return ^(NSData *data){
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    consumer(line);
  };
}

@implementation FBLineFileConsumer

+ (instancetype)synchronousReaderWithConsumer:(void (^)(NSString *))consumer
{
  return [[self alloc] initWithQueue:nil consumer:FBDataConsumerBlock(consumer)];
}

+ (instancetype)asynchronousReaderWithConsumer:(void (^)(NSString *))consumer
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBControlCore.LineConsumer", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithQueue:queue consumer:FBDataConsumerBlock(consumer)];
}

+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer
{
  return [[self alloc] initWithQueue:queue consumer:FBDataConsumerBlock(consumer)];
}

+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue dataConsumer:(void (^)(NSData *))consumer
{
  return [[self alloc] initWithQueue:queue consumer:consumer];
}

- (instancetype)initWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSData *))consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _consumer = consumer;
  _buffer = [FBLineBuffer new];

  return self;
}

- (void)consumeData:(NSData *)data
{
  @synchronized (self) {
    [self.buffer appendData:data];
    [self dispatchAvailableLines];
  }
}

- (void)consumeEndOfFile
{
  @synchronized (self) {
    [self dispatchAvailableLines];
    if (self.queue) {
      dispatch_async(self.queue, ^{
        [self tearDown];
      });
    } else {
      [self tearDown];
    }
  }
}

- (void)dispatchAvailableLines
{
  NSData *data;
  void (^consumer)(NSData *) = self.consumer;
  while ((data = [self.buffer consumeLineData])) {
    if (self.queue) {
      dispatch_async(self.queue, ^{
        consumer(data);
      });
    } else {
      consumer(data);
    }
  }
}

- (void)tearDown
{
  self.consumer = nil;
  self.queue = nil;
  self.buffer = nil;
}

@end

@interface FBAccumilatingFileConsumer ()

@property (nonatomic, strong, nullable, readonly) NSMutableData *mutableData;
@property (nonatomic, copy, nullable, readonly) NSData *finalData;

@end

@implementation FBAccumilatingFileConsumer

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
  NSAssert(self.finalData == nil, @"Cannot consume data when EOF has been consumed");
  @synchronized (self) {
    [self.mutableData appendData:data];
  }
}

- (void)consumeEndOfFile
{
  NSAssert(self.finalData == nil, @"Cannot consume EOF when EOF has been consumed");
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

- (NSArray<NSString *> *)lines
{
  NSString *output = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
  return [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
}

@end

@interface FBCompositeFileConsumer ()

@property (nonatomic, copy, readonly) NSArray<id<FBFileConsumer>> *consumers;

@end

@implementation FBCompositeFileConsumer

+ (instancetype)consumerWithConsumers:(NSArray<id<FBFileConsumer>> *)consumers
{
  return [[self alloc] initWithConsumers:consumers];
}

- (instancetype)initWithConsumers:(NSArray<id<FBFileConsumer>> *)consumers
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
  for (id<FBFileConsumer> consumer in self.consumers) {
    [consumer consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  for (id<FBFileConsumer> consumer in self.consumers) {
    [consumer consumeEndOfFile];
  }
}

@end

@implementation FBNullFileConsumer

- (void)consumeData:(NSData *)data
{
}

- (void)consumeEndOfFile
{

}

@end
