/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

 @param data the data to consume.
 */
- (void)consumeData:(NSData *)data;

/**
 Consumes an EOF.
 */
- (void)consumeEndOfFile;

@end

/**
 A specialization of a FBDataConsumer that can expose lifecycle with a Future.
 */
@protocol FBDataConsumerLifecycle <FBDataConsumer>

/**
 A Future that resolves when an EOF has been recieved.
 This is helpful for ensuring that all consumer lines have been drained.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *eofHasBeenReceived;

@end

/**
 The non-mutating methods of a buffer.
 */
@protocol FBAccumulatingBuffer <FBDataConsumerLifecycle>

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
@protocol FBConsumableBuffer <FBDataConsumerLifecycle, FBAccumulatingBuffer>

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
 Notifies when there has been consumption to a terminal

 @param terminal the terminal.
 @return a future wrapping the read data.
 */
- (FBFuture<NSData *> *)consumeAndNotifyWhen:(NSData *)terminal;

@end

/**
 Implementations of a line buffers.
 This can then be consumed based on lines/strings.
 Writes and reads are fully synchronized.
 */
@interface FBLineBuffer : NSObject

/**
 A line buffer that is only mutated through consuming data.

 @return a FBLineBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBuffer;

/**
 A line buffer that is only mutated through consuming data.

 @return a FBLineBuffer implementation.
 */
+ (id<FBAccumulatingBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data;

/**
 A line buffer that is appended to by consuming data and can be drained.

 @return a FBConsumableBuffer implementation.
 */
+ (id<FBConsumableBuffer>)consumableBuffer;

@end

/**
 A Reader of Text Data, calling the callback when a full line is available.
 */
@interface FBLineDataConsumer : NSObject <FBDataConsumer, FBDataConsumerLifecycle>

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered synchronously.

 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)synchronousReaderWithConsumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to a private queue.

 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithConsumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue consumer:(void (^)(NSString *))consumer;

/**
 Creates a Consumer of lines from a block.
 Lines will be delivered as data asynchronously to the given queue.

 @param queue the queue to call the consumer from.
 @param consumer the block to call when a line has been consumed.
 @return a new Line Reader.
 */
+ (instancetype)asynchronousReaderWithQueue:(dispatch_queue_t)queue dataConsumer:(void (^)(NSData *))consumer;

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
