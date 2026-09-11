/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>

// Protocols defined in Swift (FBDataBufferProtocols.swift)
@protocol AccumulatingBuffer;
@protocol ConsumableBuffer;
@protocol NotifyingBuffer;

/**
 Implementations of data buffers.
 Writes and reads are fully synchronized.
 */
@interface FBDataBuffer : NSObject

/**
 A data buffer that is only mutated through consuming data.

 @return a FBDataBuffer implementation.
 */
+ (nonnull id<AccumulatingBuffer>)accumulatingBuffer;

/**
 A data buffer that is only mutated through consuming data.
 Has a capacity set, if the capacity is reached, the bytes will be dropped from the beginning of the buffer.

 @param capacity the capacity in bytes of the buffer.
 @return a FBDataBuffer implementation.
 */
+ (nonnull id<AccumulatingBuffer>)accumulatingBufferWithCapacity:(size_t)capacity;

/**
 A data buffer that appends into the provided NSMutableData.

 @return a FBDataBuffer implementation.
 */
+ (nonnull id<AccumulatingBuffer>)accumulatingBufferForMutableData:(nonnull NSMutableData *)data;

/**
 A data buffer that is appended to by consuming data and can be drained.

 @return a ConsumableBuffer implementation.
 */
+ (nonnull id<ConsumableBuffer>)consumableBuffer;

/**
 A data buffer that can forward and notify.

 @return a NotifyingBuffer implementation.
 */
+ (nonnull id<NotifyingBuffer>)notifyingBuffer;

/**
 A line buffer that is appended to by consuming data that will be automatically drained by forwarding to another consumer.

 @param consumer the consumer to forward chunks to
 @param queue the queue to forward on.
 @param terminal the terminal separator.
 @return a ConsumableBuffer implementation.
 */
+ (nonnull id<NotifyingBuffer>)consumableBufferForwardingToConsumer:(nullable id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue terminal:(nullable NSData *)terminal;

/**
 NSData for a newline.
 */
+ (nonnull NSData *)newlineTerminal;

@end
