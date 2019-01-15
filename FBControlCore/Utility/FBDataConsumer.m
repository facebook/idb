// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBDataConsumer.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

@interface FBDataConsumerAdaptor ()

+ (NSData *)adaptDispatchData:(dispatch_data_t)dispatchData;

@end

@interface FBDataConsumerAdaptor_ToNSData : NSObject <FBDispatchDataConsumer>

@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

@end

@implementation FBDataConsumerAdaptor_ToNSData

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(dispatch_data_t)dispatchData
{
  NSData *data = [FBDataConsumerAdaptor adaptDispatchData:dispatchData];
  [self.consumer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.consumer consumeEndOfFile];
}

@end

@implementation FBDataConsumerAdaptor

#pragma mark Initializers

+ (id<FBDispatchDataConsumer>)dispatchDataConsumerForDataConsumer:(id<FBDataConsumer>)consumer;
{
  return [[FBDataConsumerAdaptor_ToNSData alloc] initWithConsumer:consumer];
}

#pragma mark Public

+ (NSData *)adaptDispatchData:(dispatch_data_t)dispatchData
{
  // One-way bridging of dispatch_data_t to NSData is permitted.
  // Since we can't safely assume all consumers of the NSData work discontiguous ranges, we have to make the dispatch_data contiguous.
  // This is done with dispatch_data_create_map, which is 0-copy for a contiguous range but copies for non-contiguous ranges.
  // https://twitter.com/catfish_man/status/393032222808100864
  // https://developer.apple.com/library/archive/releasenotes/Foundation/RN-Foundation-older-but-post-10.8/
  return (NSData *) dispatch_data_create_map(dispatchData, NULL, NULL);
}

@end


@interface FBLineBuffer_Accumilating : NSObject <FBDataConsumer, FBAccumulatingBuffer>

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@interface FBLineBuffer_Consumable : FBLineBuffer_Accumilating <FBConsumableBuffer>

@property (nonatomic, copy, nullable, readwrite) NSData *notificationTerminal;
@property (nonatomic, strong, nullable, readwrite) FBMutableFuture<NSData *> *notification;

@end

@implementation FBLineBuffer_Accumilating

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

@implementation FBLineBuffer_Consumable

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
  return [self consumeUntil:FBLineBuffer_Accumilating.newlineTerminal];
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

@implementation FBLineBuffer

#pragma mark Initializers

+ (id<FBAccumulatingBuffer>)accumulatingBuffer
{
  return [FBLineBuffer_Accumilating new];
}

+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data
{
  return [[FBLineBuffer_Accumilating alloc] initWithBackingBuffer:data];
}

+ (id<FBConsumableBuffer>)consumableBuffer
{
  return [FBLineBuffer_Consumable new];
}

@end

@interface FBLineDataConsumer ()

@property (nonatomic, strong, nullable, readwrite) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) void (^consumer)(NSData *);
@property (nonatomic, strong, readwrite) id<FBConsumableBuffer> buffer;
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
