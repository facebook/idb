/**
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 */
@protocol FBConsumableBuffer <FBAccumulatingBuffer>

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

/**
 Consumes until data recieved.

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

/**
 Forwards to another data consumer, notifying every time a terminal is passed.
 The consumer is called synchronously on the queue.

 @param consumer the consumer to forward to.
 @param terminal the terminal to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)consume:(id<FBDataConsumer>)consumer untilTerminal:(NSData *)terminal error:(NSError **)error;

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
 Removes the forwarding consumer, if one is present.

 @return the consumer, if present.
 */
- (nullable id<FBDataConsumer>)removeForwardingConsumer;

/**
 Notifies when there has been consumption to a terminal

 @param terminal the terminal.
 @return a future wrapping the read data.
 */
- (FBFuture<NSData *> *)consumeAndNotifyWhen:(NSData *)terminal;

@end

/**
 Implementations of data buffers.
 Writes and reads are fully synchronized.
 */
@interface FBDataBuffer : NSObject

/**
 A line buffer that is only mutated through consuming data.

 @return a FBDataBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBuffer;

/**
 A line buffer that is only mutated through consuming data.

 @return a FBDataBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data;

/**
 A line buffer that is appended to by consuming data and can be drained.

 @return a FBConsumableBuffer implementation.
 */
+ (id<FBConsumableBuffer>)consumableBuffer;

/**
 A line buffer that is appended to by consuming data that will be automatically drained by forwarding to another consumer.

 @param consumer the consumer to forward chunks to
 @param queue the queue to forward on.
 @param terminal the terminal separator.
 @return a FBConsumableBuffer implementation.
 */
+ (id<FBConsumableBuffer>)consumableBufferForwardingToConsumer:(nullable id<FBDataConsumer>)consumer onQueue:(nullable dispatch_queue_t)queue terminal:(nullable NSData *)terminal;

/**
 NSData for a newline.
 */
+ (NSData *)newlineTerminal;

@end

NS_ASSUME_NONNULL_END
