/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DataConsumer.h"

#import <stdatomic.h>

#import "ControlCoreLogger.h"
#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"
#import "FBDataBuffer.h"

@interface FBDataConsumerAdaptor ()

+ (dispatch_data_t)adaptNSData:(NSData *)dispatchData;

@end

@interface FBDataConsumerAdaptor_ToNSData : NSObject <DispatchDataConsumer>

@property (nonatomic, readonly, strong) id<DataConsumer> consumer;

@end

@implementation FBDataConsumerAdaptor_ToNSData

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<DataConsumer>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

#pragma mark DataConsumer

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

@interface FBDataConsumerAdaptor_ToDispatchData : NSObject <DataConsumer, DataConsumerLifecycle>

@property (nonatomic, readonly, strong) id<DispatchDataConsumer, DataConsumerLifecycle> consumer;

@end

// Subclass used when the wrapped consumer is itself synchronous, so callers that
// branch on `-conformsToProtocol:@protocol(DataConsumerSync)` (e.g.
// SimulatorVideoStream's zero-copy fast path) can still find the marker.
@interface FBDataConsumerAdaptor_SyncToDispatchData : FBDataConsumerAdaptor_ToDispatchData <DataConsumerSync>
@end

@implementation FBDataConsumerAdaptor_SyncToDispatchData
@end

@implementation FBDataConsumerAdaptor_ToDispatchData

#pragma mark Initializers

- (instancetype)initWithConsumer:(id<DispatchDataConsumer, DataConsumerLifecycle>)consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  dispatch_data_t dispatchData = [FBDataConsumerAdaptor adaptNSData:data];
  [self.consumer consumeData:dispatchData];
}

- (void)consumeEndOfFile
{
  [self.consumer consumeEndOfFile];
}

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.consumer.finishedConsuming;
}

@end

@implementation FBDataConsumerAdaptor

#pragma mark Initializers

+ (id<DispatchDataConsumer>)dispatchDataConsumerForDataConsumer:(id<DataConsumer>)consumer;
{
  return [[FBDataConsumerAdaptor_ToNSData alloc] initWithConsumer:consumer];
}

+ (id<DataConsumer, DataConsumerLifecycle>)dataConsumerForDispatchDataConsumer:(id<DispatchDataConsumer, DataConsumerLifecycle>)consumer;
{
  Class adaptorClass = [consumer conformsToProtocol:@protocol(DataConsumerSync)]
  ? [FBDataConsumerAdaptor_SyncToDispatchData class]
  : [FBDataConsumerAdaptor_ToDispatchData class];
  return [[adaptorClass alloc] initWithConsumer:consumer];
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

#pragma mark Private

+ (dispatch_data_t)adaptNSData:(NSData *)data __attribute__((no_sanitize("nullability-arg")))
{
  // DISPATCH_DATA_DESTRUCTOR_DEFAULT copies the bytes, so the dispatch_data stays valid and immutable
  // even when `data` is secretly an NSMutableData (e.g. from -[NSString dataUsingEncoding:]).
  return dispatch_data_create(
    data.bytes,
    data.length,
    dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),
    DISPATCH_DATA_DESTRUCTOR_DEFAULT
  );
}

@end

typedef void (^dataBlock)(NSData *);
static inline dataBlock FBDataConsumerToStringConsumer(void (^consumer)(NSString *))
{
  return ^(NSData *data) {
    NSString *line = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (line == nil) {
      line = @"non-utf8";
    }
    consumer(line);
  };
}

@interface FBBlockDataConsumer_Dispatcher : NSObject <DataConsumer>

@property (nullable, nonatomic, readwrite, strong) dispatch_queue_t queue;
@property (nullable, nonatomic, readwrite, strong) dispatch_group_t group;
@property (nullable, nonatomic, readwrite, copy) void (^consumer)(NSData *);
@property _Atomic int64_t numPendingTasks;

@end

@implementation FBBlockDataConsumer_Dispatcher

- (instancetype)initWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSData *))consumer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _group = dispatch_group_create();
  _consumer = consumer;
  atomic_init(&_numPendingTasks, 0);

  return self;
}

- (void)consumeData:(NSData *)data
{
  void (^consumer)(NSData *) = nil;
  dispatch_queue_t queue;
  dispatch_group_t group;
  atomic_fetch_add(&_numPendingTasks, 1);
  @synchronized(self)
  {
    consumer = self.consumer;
    queue = self.queue;
    group = self.group;
    if (!consumer) {
      return;
    }
    if (queue) {
      dispatch_group_async(group,
        queue, ^{
          consumer(data);
          atomic_fetch_sub(&self->_numPendingTasks, 1);
        });
    } else {
      consumer(data);
      atomic_fetch_sub(&_numPendingTasks, 1);
    }
  }
}

- (void)consumeEndOfFile
{
  dispatch_group_t group;
  @synchronized(self)
  {
    group = self.group;
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    self.group = nil;
    self.consumer = nil;
    self.queue = nil;
  }
}

@end

@interface FBBlockDataConsumer () <DataConsumer, DataConsumerLifecycle>

@property (nonatomic, readonly, strong) FBBlockDataConsumer_Dispatcher *dispatcher;

@end

@interface FBBlockDataConsumerAsync : NSObject <DataConsumer, DataConsumerLifecycle, DataConsumerAsync>

@property (nonatomic, readonly, strong) FBBlockDataConsumer_Dispatcher *dispatcher;

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher;

@end

@interface FBBlockDataConsumer_Buffered : FBBlockDataConsumer

@property (nonatomic, readonly, strong) id<ConsumableBuffer> buffer;

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher terminal:(NSData *)terminal;

@end

// Used when the dispatcher has no queue (synchronous delivery), so callers that
// branch on `-conformsToProtocol:@protocol(DataConsumerSync)` find the marker.
@interface FBBlockDataConsumer_Buffered_Sync : FBBlockDataConsumer_Buffered <DataConsumerSync>
@end

@implementation FBBlockDataConsumer_Buffered_Sync
@end

@interface FBBlockDataConsumer_Unbuffered : FBBlockDataConsumer <DataConsumerSync>

@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *finishedConsumingFuture;

@end

@interface FBBlockDataConsumerAsync_Unbuffered : FBBlockDataConsumerAsync

@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *finishedConsumingFuture;

@end

@implementation FBBlockDataConsumer

#pragma mark Initializers

+ (id<DataConsumer, DataConsumerLifecycle>)synchronousDataConsumerWithBlock:(void (^)(NSData *))consumer
{
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:nil consumer:consumer];
  return [[FBBlockDataConsumer_Unbuffered alloc] initWithDispatcher:dispatcher];
}

+ (id<DataConsumer, DataConsumerLifecycle>)synchronousLineConsumerWithBlock:(void (^)(NSString *))consumer
{
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:nil consumer:FBDataConsumerToStringConsumer(consumer)];
  return [[FBBlockDataConsumer_Buffered_Sync alloc] initWithDispatcher:dispatcher terminal:FBDataBuffer.newlineTerminal];
}

+ (id<DataConsumer, DataConsumerLifecycle, DataConsumerAsync>)asynchronousDataConsumerOnQueue:(dispatch_queue_t)queue consumer:(void (^)(NSData *))consumer
{
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:queue consumer:consumer];
  return [[FBBlockDataConsumerAsync_Unbuffered alloc] initWithDispatcher:dispatcher];
}

+ (id<DataConsumer, DataConsumerLifecycle, DataConsumerAsync>)asynchronousDataConsumerWithBlock:(void (^)(NSData *))consumer
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBControlCore.BlockDataConsumer.data", DISPATCH_QUEUE_SERIAL);
  return [self asynchronousDataConsumerOnQueue:queue consumer:consumer];
}

+ (id<DataConsumer, DataConsumerLifecycle>)asynchronousLineConsumerWithBlock:(void (^)(NSString *))consumer
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBControlCore.BlockDataConsumer.lines", DISPATCH_QUEUE_SERIAL);
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:queue consumer:FBDataConsumerToStringConsumer(consumer)];
  return [[FBBlockDataConsumer_Buffered alloc] initWithDispatcher:dispatcher terminal:FBDataBuffer.newlineTerminal];
}

+ (id<DataConsumer, DataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer
{
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:queue consumer:FBDataConsumerToStringConsumer(consumer)];
  return [[FBBlockDataConsumer_Buffered alloc] initWithDispatcher:dispatcher terminal:FBDataBuffer.newlineTerminal];
}

+ (id<DataConsumer, DataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(dispatch_queue_t)queue dataConsumer:(void (^)(NSData *))consumer
{
  FBBlockDataConsumer_Dispatcher *dispatcher = [[FBBlockDataConsumer_Dispatcher alloc] initWithQueue:queue consumer:consumer];
  return [[FBBlockDataConsumer_Buffered alloc] initWithDispatcher:dispatcher terminal:FBDataBuffer.newlineTerminal];
}

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dispatcher = dispatcher;

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)consumeEndOfFile
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBBlockDataConsumerAsync

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _dispatcher = dispatcher;

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)consumeEndOfFile
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark DataConsumerAsync

- (NSInteger)unprocessedDataCount
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

@end

@implementation FBBlockDataConsumer_Buffered

#pragma mark Initializers

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher terminal:(NSData *)terminal
{
  self = [super initWithDispatcher:dispatcher];
  if (!self) {
    return nil;
  }

  _buffer = [FBDataBuffer consumableBufferForwardingToConsumer:dispatcher onQueue:nil terminal:terminal];

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized(self) {
    [self.buffer consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized(self) {
    [self.buffer consumeEndOfFile];
  }
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.buffer.finishedConsuming;
}

@end

@implementation FBBlockDataConsumer_Unbuffered

#pragma mark Initializers

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher
{
  self = [super initWithDispatcher:dispatcher];
  if (!self) {
    return nil;
  }

  _finishedConsumingFuture = FBMutableFuture.future;

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized(self) {
    [self.dispatcher consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized(self) {
    [self.dispatcher consumeEndOfFile];
    [self.finishedConsumingFuture resolveWithResult:NSNull.null];
  }
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingFuture;
}

@end

@implementation FBBlockDataConsumerAsync_Unbuffered

#pragma mark Initializers

- (instancetype)initWithDispatcher:(FBBlockDataConsumer_Dispatcher *)dispatcher
{
  self = [super initWithDispatcher:dispatcher];
  if (!self) {
    return nil;
  }

  _finishedConsumingFuture = FBMutableFuture.future;

  return self;
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  @synchronized(self) {
    [self.dispatcher consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  @synchronized(self) {
    [self.dispatcher consumeEndOfFile];
    [self.finishedConsumingFuture resolveWithResult:NSNull.null];
  }
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingFuture;
}

#pragma mark DataConsumerAsync

- (NSInteger)unprocessedDataCount
{
  // Deliberately unsynchronized: the count is only ever approximate.
  return self.dispatcher.numPendingTasks;
}

@end

@implementation FBLoggingDataConsumer

#pragma mark Initializers

+ (instancetype)consumerWithLogger:(id<ControlCoreLogger>)logger
{
  return [[self alloc] initWithLogger:logger];
}

- (instancetype)initWithLogger:(id<ControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;

  return self;
}

#pragma mark DataConsumer

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
{}

@end

@interface FBCompositeDataConsumer ()

@property (nonatomic, readonly, copy) NSArray<id<DataConsumer>> *consumers;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *finishedConsumingFuture;

@end

@implementation FBCompositeDataConsumer

#pragma mark Initializers

+ (instancetype)consumerWithConsumers:(NSArray<id<DataConsumer>> *)consumers
{
  return [[self alloc] initWithConsumers:consumers];
}

- (instancetype)initWithConsumers:(NSArray<id<DataConsumer>> *)consumers
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumers = consumers;
  _finishedConsumingFuture = FBMutableFuture.future;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Composite Consumer %@", [CollectionInformation oneLineDescriptionFromArray:self.consumers]];
}

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{
  for (id<DataConsumer> consumer in self.consumers) {
    [consumer consumeData:data];
  }
}

- (void)consumeEndOfFile
{
  for (id<DataConsumer> consumer in self.consumers) {
    [consumer consumeEndOfFile];
  }
  [self.finishedConsumingFuture resolveWithResult:NSNull.null];
}

#pragma mark DataConsumerLifecycle

- (FBFuture<NSNull *> *)finishedConsuming
{
  return self.finishedConsumingFuture;
}

@end

@implementation FBNullDataConsumer

#pragma mark DataConsumer

- (void)consumeData:(NSData *)data
{}

- (void)consumeEndOfFile
{}

@end
