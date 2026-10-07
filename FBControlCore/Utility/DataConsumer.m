/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DataConsumer.h"

#import <stdatomic.h>

#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"

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
