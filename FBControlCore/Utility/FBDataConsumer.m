// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBDataConsumer.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

@interface FBLineBuffer_Accumilating : NSObject <FBAccumulatingLineBuffer>

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) NSData *terminalData;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@interface FBLineBuffer_Consumable : FBLineBuffer_Accumilating <FBConsumableLineBuffer>

@end

@implementation FBLineBuffer_Accumilating

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
  _terminalData = [NSData dataWithBytes:"\n" length:1];
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

@implementation FBLineBuffer_Consumable

#pragma mark NSObject

- (NSString *)description
{
  @synchronized (self) {
    return [NSString stringWithFormat:@"Consumable Buffer %lu Bytes", self.data.length];
  }
}

#pragma mark FBConsumableLineBuffer

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

- (nullable NSData *)consumeLineData
{
  if (self.buffer.length == 0) {
    return nil;
  }
  NSRange newlineRange = [self.buffer rangeOfData:self.terminalData options:0 range:NSMakeRange(0, self.buffer.length)];
  if (newlineRange.location == NSNotFound) {
    return nil;
  }
  NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
  [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:"" length:0];
  return lineData;
}

- (nullable NSString *)consumeLineString
{
  NSData *lineData = self.consumeLineData;
  if (!lineData) {
    return nil;
  }
  return [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
}

@end

@implementation FBLineBuffer

#pragma mark Initializers

+ (id<FBAccumulatingLineBuffer>)accumulatingBuffer
{
  return [FBLineBuffer_Accumilating new];
}

+ (id<FBAccumulatingLineBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data
{
  return [[FBLineBuffer_Accumilating alloc] initWithBackingBuffer:data];
}

+ (id<FBConsumableLineBuffer>)consumableBuffer
{
  return [FBLineBuffer_Consumable new];
}

@end

@interface FBLineDataConsumer ()

@property (nonatomic, strong, nullable, readwrite) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) void (^consumer)(NSData *);
@property (nonatomic, strong, readwrite) id<FBConsumableLineBuffer> buffer;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

typedef void (^dataBlock)(NSData *);
static inline dataBlock FBDataConsumerBlock (void(^consumer)(NSString *)) {
  return ^(NSData *data){
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    consumer(line);
  };
}

@implementation FBLineDataConsumer

#pragma mark Initializers

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
  _buffer = FBLineBuffer.consumableBuffer;
  _eofHasBeenReceivedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized (self) {
    [self.buffer consumeData:data];
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

#pragma mark FBDataConsumerLifecycle

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedFuture;
}

#pragma mark Private

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
  [self.eofHasBeenReceivedFuture resolveWithResult:NSNull.null];
}

@end

@implementation FBLoggingDataConsumer

#pragma mark Initializers

+ (instancetype)consumerWithLogger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithLogger:logger];
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!string) {
    return;
  }
  string = [string stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
  if (string.length < 1) {
    return;
  }
  [self.logger log:string];
}

- (void)consumeEndOfFile
{

}

@end

@interface FBCompositeDataConsumer ()

@property (nonatomic, copy, readonly) NSArray<id<FBDataConsumer>> *consumers;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@implementation FBCompositeDataConsumer

#pragma mark Initializers

+ (instancetype)consumerWithConsumers:(NSArray<id<FBDataConsumer>> *)consumers
{
  return [[self alloc] initWithConsumers:consumers];
}

- (instancetype)initWithConsumers:(NSArray<id<FBDataConsumer>> *)consumers
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumers = consumers;
  _eofHasBeenReceivedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Composite Consumer %@", [FBCollectionInformation oneLineDescriptionFromArray:self.consumers]];
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  for (id<FBDataConsumer> consumer in self.consumers) {
    [consumer consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  for (id<FBDataConsumer> consumer in self.consumers) {
    [consumer consumeEndOfFile];
  }
  [self.eofHasBeenReceivedFuture resolveWithResult:NSNull.null];
}

#pragma mark FBDataConsumerLifecycle

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedFuture;
}

@end

@implementation FBNullDataConsumer

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
}

- (void)consumeEndOfFile
{

}

@end
