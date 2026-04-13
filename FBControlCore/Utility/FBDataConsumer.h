/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

// Protocols defined in Swift (FBDataConsumer.swift)
@protocol FBDataConsumer;
@protocol FBDispatchDataConsumer;
@protocol FBDataConsumerSync;
@protocol FBDataConsumerAsync;
@protocol FBDataConsumerLifecycle;

/**
 Adapts a NSData consumer to a dispatch_data consumer to.
 */
@interface FBDataConsumerAdaptor : NSObject

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a dispatch_data consumer.
 */
+ (nonnull id<FBDispatchDataConsumer>)dispatchDataConsumerForDataConsumer:(nonnull id<FBDataConsumer>)consumer;

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a NSData consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle>)dataConsumerForDispatchDataConsumer:(nonnull id<FBDispatchDataConsumer, FBDataConsumerLifecycle>)consumer;

/**
 Converts dispatch_data to NSData.
 Note that this will copy data if the underlying dispatch data is non-contiguous.

 @param dispatchData the data to adapt.
 @return NSData from the dispatchData.
 */
+ (nonnull NSData *)adaptDispatchData:(nonnull dispatch_data_t)dispatchData;

@end

/**
 A consumer of data, passing output to a block.
 */
@interface FBBlockDataConsumer : NSObject

/**
 Creates a consumer that delivers data when available.
 Data will be delivered synchronously.

 @param consumer the block to call when new data is available
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)synchronousDataConsumerWithBlock:(void (^_Nonnull)(NSData * _Nonnull))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered synchronously.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)synchronousLineConsumerWithBlock:(void (^_Nonnull)(NSString * _Nonnull))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to the provided queue.

 @param queue the queue to consume on.
 @param consumer the block to call when new data is available
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerAsync>)asynchronousDataConsumerOnQueue:(nonnull dispatch_queue_t)queue consumer:(void (^_Nonnull)(NSData * _Nonnull))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerAsync>)asynchronousDataConsumerWithBlock:(void (^_Nonnull)(NSData * _Nonnull))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithBlock:(void (^_Nonnull)(NSString * _Nonnull))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(nonnull dispatch_queue_t)queue consumer:(void (^_Nonnull)(NSString * _Nonnull))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered as data asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (nonnull id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(nonnull dispatch_queue_t)queue dataConsumer:(void (^_Nonnull)(NSData * _Nonnull))consumer;

@end

@protocol FBControlCoreLogger;

/**
 A consumer that logs received data to a logger.
 */
@interface FBLoggingDataConsumer : NSObject

/**
 The Designated Initializer
 */
+ (nonnull instancetype)consumerWithLogger:(nonnull id<FBControlCoreLogger>)logger;

/**
 The wrapped logger.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

- (void)consumeData:(nonnull NSData *)data;
- (void)consumeEndOfFile;

@end

/**
 A Composite Consumer.
 */
@interface FBCompositeDataConsumer : NSObject

/**
 A Consumer of Consumers.

 @param consumers the consumers to compose.
 @return a new consumer.
 */
+ (nonnull instancetype)consumerWithConsumers:(nonnull NSArray<id<FBDataConsumer>> *)consumers;

- (void)consumeData:(nonnull NSData *)data;
- (void)consumeEndOfFile;
@property (nonnull, nonatomic, readonly, strong) FBFuture<NSNull *> *finishedConsuming;

@end

/**
 A consumer that does nothing with the data.
 */
@interface FBNullDataConsumer : NSObject

- (void)consumeData:(nonnull NSData *)data;
- (void)consumeEndOfFile;

@end
