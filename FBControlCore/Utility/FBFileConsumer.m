// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBFileConsumer.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"

@interface FBLineBuffer ()

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) NSData *terminalData;

@end

@implementation FBLineBuffer

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _buffer = [NSMutableData data];
  _terminalData = [NSData dataWithBytes:"\n" length:1];

  return self;
}

#pragma mark Public Methods

- (nullable NSData *)consumeCurrentData
{
  NSData *data = [self.buffer copy];
  self.buffer.data = NSData.data;
  return data;
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

#pragma mark FBFileConsumer

- (void)consumeData:(NSData *)data
{
  [self.buffer appendData:data];
}

- (void)consumeEndOfFile
{

}

@end

@interface FBLineFileConsumer ()

@property (nonatomic, strong, nullable, readwrite) dispatch_queue_t queue;
@property (nonatomic, copy, nullable, readwrite) void (^consumer)(NSData *);
@property (nonatomic, strong, readwrite) FBLineBuffer *buffer;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

typedef void (^dataBlock)(NSData *);
static inline dataBlock FBDataConsumerBlock (void(^consumer)(NSString *)) {
  return ^(NSData *data){
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    consumer(line);
  };
}

@implementation FBLineFileConsumer

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
  _buffer = [FBLineBuffer new];
  _eofHasBeenReceivedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark FBFileConsumer

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

#pragma mark FBFileConsumerLifecycle

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

@interface FBAccumilatingFileConsumer ()

@property (nonatomic, strong, nullable, readonly) NSMutableData *mutableData;
@property (nonatomic, copy, nullable, readonly) NSData *finalData;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *eofHasBeenReceivedFuture;

@end

@implementation FBAccumilatingFileConsumer

#pragma mark Initializers

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
  _eofHasBeenReceivedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark FBFileConsumer

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
    [self.eofHasBeenReceivedFuture resolveWithResult:NSNull.null];
  }
}

#pragma mark FBFileConsumerLifecycle

- (FBFuture<NSNull *> *)eofHasBeenReceived
{
  return self.eofHasBeenReceivedFuture;
}

#pragma mark Public

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

@implementation FBLoggingFileConsumer

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

#pragma mark FBFileConsumer

- (void)consumeData:(NSData *)data
{
  NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!string) {
    return;
  }
  [self.logger log:string];
}

- (void)consumeEndOfFile
{

}


@end

@interface FBCompositeFileConsumer ()

@property (nonatomic, copy, readonly) NSArray<id<FBFileConsumer>> *consumers;

@end

@implementation FBCompositeFileConsumer

#pragma mark Initializers

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

#pragma mark FBFileConsumer

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

#pragma mark FBFileConsumer

- (void)consumeData:(NSData *)data
{
}

- (void)consumeEndOfFile
{

}

@end
