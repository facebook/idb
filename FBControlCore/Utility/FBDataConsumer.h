/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A consumer of NSData.
 */
@protocol FBDataConsumer <NSObject>

/**
 Consumes the provided binary data.
 If the receiver implements FBDataConsumerSync, then stack allocated data is permitted.
 Otherwise, the underlying buffer must survive data being consumed on a separate thread.

 @param data the data to consume.
 */
- (void)consumeData:(NSData *)data;

/**
 Consumes an end-of-file.
 */
- (void)consumeEndOfFile;

@end

/**
 A consumer of dispatch_data.
 */
@protocol FBDispatchDataConsumer <NSObject>

/**
 Consumes the provided binary data.

 @param data the data to consume.
 */
- (void)consumeData:(dispatch_data_t)data;

/**
 Consumes an end-of-file.
 */
- (void)consumeEndOfFile;

@end

/**
 Consumer which consumes the data synchronously in the same context as the caller invoking consumeData
 Members of this protocol will have any underlying data buffers that are passed in within `consumeData:`.
 This allows the caller to avoid copying data that may be stack-allocated.
 This is exposed as a more restrictive type in order to prevent non-stack consuming implementors performing a use-after-free.
 */
@protocol FBDataConsumerSync <NSObject>

@end

/**
 Consumer which consumes the data asynchronously
 The data passed in to this consumer should not contain a pointer to a stack allocated data and it should be copied instead
 */
@protocol FBDataConsumerAsync <NSObject>

/**
Number of submitted data that has not been consumed yet
*/
- (NSInteger)unprocessedDataCount;

@end

/**
 Observation of a Data Consumer's lifecycle
 */
@protocol FBDataConsumerLifecycle <NSObject>

/**
 A Future that resolves when an there is no more data to write and any underlying resource managed by the consumer is released.
 At this point, consumers are safe to assume that any resource that the writer is wrapping is safe to use.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *finishedConsuming;

@end

/**
 Adapts a NSData consumer to a dispatch_data consumer to.
 */
@interface FBDataConsumerAdaptor : NSObject

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a dispatch_data consumer.
 */
+ (id<FBDispatchDataConsumer>)dispatchDataConsumerForDataConsumer:(id<FBDataConsumer>)consumer;

/**
 Adapts a NSData consumer to a dispatch_data consumer.

 @param consumer the consumer to adapt.
 @return a NSData consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle>)dataConsumerForDispatchDataConsumer:(id<FBDispatchDataConsumer, FBDataConsumerLifecycle>)consumer;

/**
 Converts dispatch_data to NSData.
 Note that this will copy data if the underlying dispatch data is non-contiguous.

 @param dispatchData the data to adapt.
 @return NSData from the dispatchData.
 */
+ (NSData *)adaptDispatchData:(dispatch_data_t)dispatchData;

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
+ (id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)synchronousDataConsumerWithBlock:(void (^)(NSData *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered synchronously.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerSync>)synchronousLineConsumerWithBlock:(void (^)(NSString *))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to the provided queue.

 @param queue the queue to consume on.
 @param consumer the block to call when new data is available
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerAsync>)asynchronousDataConsumerOnQueue:(dispatch_queue_t)queue consumer:(void (^)(NSData *))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle, FBDataConsumerAsync>)asynchronousDataConsumerWithBlock:(void (^)(NSData *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithBlock:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered as data asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new consumer.
 */
+ (id<FBDataConsumer, FBDataConsumerLifecycle>)asynchronousLineConsumerWithQueue:(dispatch_queue_t)queue dataConsumer:(void (^)(NSData *))consumer;

@end

@protocol FBControlCoreLogger;

/**
 A consumer that does nothing with the data.
 */
@interface FBLoggingDataConsumer : NSObject <FBDataConsumer>

/**
 The Designated Initializer
 */
+ (instancetype)consumerWithLogger:(id<FBControlCoreLogger>)logger;

/**
 The wrapped logger.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

/**
 A Composite Consumer.
 */
@interface FBCompositeDataConsumer : NSObject <FBDataConsumer, FBDataConsumerLifecycle>

/**
 A Consumer of Consumers.

 @param consumers the consumers to compose.
 @return a new consumer.
 */
+ (instancetype)consumerWithConsumers:(NSArray<id<FBDataConsumer>> *)consumers;

@end

/**
 A consumer that does nothing with the data.
 */
@interface FBNullDataConsumer : NSObject <FBDataConsumer>

@end

NS_ASSUME_NONNULL_END
