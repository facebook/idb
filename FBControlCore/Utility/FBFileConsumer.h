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

@protocol FBControlCoreLogger;

/**
 A Consumer of a File's Data.
 */
@protocol FBFileConsumer <NSObject>

/**
 Consumes the provided text data.

 @param data the data to consume.
 */
- (void)consumeData:(NSData *)data;

/**
 Consumes an EOF.
 */
- (void)consumeEndOfFile;

@end

/**
 A specialization of a FBFileConsumer that can expose lifecycle with a Future.
 */
@protocol FBFileConsumerLifecycle <FBFileConsumer>

/**
 A Future that resolves when an EOF has been recieved.
 This is helpful for ensuring that all consumer lines have been drained.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *eofHasBeenReceived;

@end

/**
 The Non-mutating methods of a line reader.
 */
@protocol FBAccumulatingLineBuffer <FBFileConsumerLifecycle>

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
 The Mutating Methods of a line reader.
 */
@protocol FBConsumableLineBuffer <FBFileConsumerLifecycle, FBAccumulatingLineBuffer>

/**
 Consume the remainder of the buffer available, returning it as Data.
 This will flush the entirity of the buffer.
 */
- (nullable NSData *)consumeCurrentData;

/**
 Consume the remainder of the buffer available, returning it as a String.
 This will flush the entirity of the buffer.
 */
- (nullable NSString *)consumeCurrentString;

/**
 Consume a line if one is available, returning it as Data.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSData *)consumeLineData;

/**
 Consume a line if one is available, returning it as a String.
 This will flush the buffer of the lines that are consumed.
 */
- (nullable NSString *)consumeLineString;

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
+ (id<FBAccumulatingLineBuffer>)accumulatingBuffer;

/**
 A line buffer that is only mutated through consuming data.

 @return a FBLineBuffer implementation.
 */
+ (id<FBAccumulatingLineBuffer>)accumulatingBufferForMutableData:(NSMutableData *)data;

/**
 A line buffer that is appended to by consuming data and can be drained.

 @return a FBConsumableLineBuffer implementation.
 */
+ (id<FBConsumableLineBuffer>)consumableBuffer;

@end

/**
 A Reader of Text Data, calling the callback when a full line is available.
 */
@interface FBLineFileConsumer : NSObject <FBFileConsumer, FBFileConsumerLifecycle>

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

/**
 A consumer that does nothing with the data.
 */
@interface FBLoggingFileConsumer : NSObject <FBFileConsumer>

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
@interface FBCompositeFileConsumer : NSObject <FBFileConsumer, FBFileConsumerLifecycle>

/**
 A Consumer of Consumers.

 @param consumers the consumers to compose.
 @return a new consumer.
 */
+ (instancetype)consumerWithConsumers:(NSArray<id<FBFileConsumer>> *)consumers;

@end

/**
 A consumer that does nothing with the data.
 */
@interface FBNullFileConsumer : NSObject <FBFileConsumer>

@end

NS_ASSUME_NONNULL_END
