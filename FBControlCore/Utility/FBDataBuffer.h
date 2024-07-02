/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The non-mutating methods of a buffer.
 */
@protocol FBAccumulatingBuffer <FBDataConsumer, FBDataConsumerLifecycle>

/**
 Obtains a copy of the current output data.
 */
- (NSData *)data;

/**
 Obtains a copy of the current output data.
 */
- (NSArray<NSString *> *)lines;

@end

/**
 The mutating methods of a buffer.
 All of the methods at this protocol level define synchronous consumption.
 All of the methods defined at this level are fully synchronized, so they can be called at the same time as append functions at the FBDataConsumer level.
 */
@protocol FBConsumableBuffer <FBAccumulatingBuffer>

#pragma mark Polling Operations

/**
 Consume the remainder of the buffer available, returning it as Data.
 This will flush the entirity of the buffer.

 @return all the current data in the buffer.
 */
- (nullable NSData *)consumeCurrentData;

/**
 Consume the remainder of the buffer available, returning it as a String.
 This will flush the entirity of the buffer.

 @return all the current data in the buffer as a string.
 */
- (nullable NSString *)consumeCurrentString;

/*/
 Consumes an amount of data from the buffer.

 @param length the length of data to consume.
 @return all the data if there's enough, nil otherwise.
 */
- (nullable NSData *)consumeLength:(NSUInteger)length;

/**
 Consumes until data received.

 @param terminal the terminal.
 @return all the data before the separator if there is data to consume, nil otherwise.
 */
- (nullable NSData *)consumeUntil:(NSData *)terminal;

/**
 Consume a line if one is available, returning it as Data.
 This will flush the buffer of the lines that are consumed.

 @return all the data before a newline if there is data to consume, nil otherwise.
 */
- (nullable NSData *)consumeLineData;

/**
 Consume a line if one is available, returning it as a String.
 This will flush the buffer of the lines that are consumed.

 @return all the data before a newline as a string if there is data to consume, nil otherwise.
 */
- (nullable NSString *)consumeLineString;

@end

/**
 A Consumable buffer that also allows forwarding and notifying.
 */
@protocol FBNotifyingBuffer <FBConsumableBuffer>


/**
 Forwards to another data consumer, notifying every time a terminal is passed.
 The consumer is called asynchronously on the queue.

 @param consumer the consumer to forward to.
 @param queue the queue to notify on.
 @param terminal the terminal to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)consume:(id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue untilTerminal:(NSData *)terminal error:(NSError **)error;

/**
 Notifies when there has been consumption to a terminal

 @param terminal the terminal.
 @return a future wrapping the read data.
 */
- (FBFuture<NSData *> *)consumeAndNotifyWhen:(NSData *)terminal;

/**
 Consumes based upon a fixed-length header, that can be parsed.
 The value derived from the parsing of the header defines the remainder of the data to read.

 @param headerLength the fixed-length of the header.
 @param derivedLength the derived length of the payload
 @return a Future wrapping the payload, based on the derived length.
 */
- (FBFuture<NSData *> *)consumeHeaderLength:(NSUInteger)headerLength derivedLength:(NSUInteger(^)(NSData *))derivedLength;

@end

/**
 Implementations of data buffers.
 Writes and reads are fully synchronized.
 */
@interface FBDataBuffer : NSObject

/**
 A data buffer that is only mutated through consuming data.

 @return a FBDataBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBuffer;

/**
 A data buffer that is only mutated through consuming data.
 Has a capacity set, if the capacity is reached, the bytes will be dropped from the beginning of the buffer.

 @param capacity the capacity in bytes of the buffer.
 @return a FBDataBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBufferWithCapacity:(size_t)capacity;

/**
 A data buffer that is only mutated through consuming data.

 @return a FBDataBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data;

/**
 A data buffer that is appended to by consuming data and can be drained.

 @return a FBConsumableBuffer implementation.
 */
+ (id<FBConsumableBuffer>)consumableBuffer;

/**
 A data buffer that can forward and notify.

 @return a FBNotifyingBuffer implementation.
 */
+ (id<FBNotifyingBuffer>)notifyingBuffer;

/**
 A line buffer that is appended to by consuming data that will be automatically drained by forwarding to another consumer.

 @param consumer the consumer to forward chunks to
 @param queue the queue to forward on.
 @param terminal the terminal separator.
 @return a FBConsumableBuffer implementation.
 */
+ (id<FBNotifyingBuffer>)consumableBufferForwardingToConsumer:(nullable id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue terminal:(nullable NSData *)terminal;

/**
 NSData for a newline.
 */
+ (NSData *)newlineTerminal;

@end

NS_ASSUME_NONNULL_END
