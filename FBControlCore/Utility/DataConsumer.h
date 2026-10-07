/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

// Protocols defined in Swift (DataConsumer.swift)
@protocol DataConsumer;
@protocol DataConsumerSync;
@protocol DataConsumerAsync;
@protocol DataConsumerLifecycle;

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
+ (nonnull id<DataConsumer, DataConsumerLifecycle, DataConsumerSync>)synchronousDataConsumerWithBlock:(void (^_Nonnull)(NSData * _Nonnull))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to the provided queue.

 @param queue the queue to consume on.
 @param consumer the block to call when new data is available
 @return a new consumer.
 */
+ (nonnull id<DataConsumer, DataConsumerLifecycle, DataConsumerAsync>)asynchronousDataConsumerOnQueue:(nonnull dispatch_queue_t)queue consumer:(void (^_Nonnull)(NSData * _Nonnull))consumer;

/**
 Creates a consumer that delivers data when available.
 Data will be delivered asynchronously to a private queue.

 @param consumer the block to call when new data is available
 @return a new consumer.
 */
+ (nonnull id<DataConsumer, DataConsumerLifecycle, DataConsumerAsync>)asynchronousDataConsumerWithBlock:(void (^_Nonnull)(NSData * _Nonnull))consumer;

@end
