/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
 Wraps FBFileConsumer Implementations with the ability to await EOF events.
 */
@interface FBAwaitableFileDataConsumer : NSObject<FBFileConsumer>

/**
 Creates an Awaitable File Data Consumer.

 @param consumer the underlying consumer
 @return a new Data Consumer.
 */
+ (instancetype)consumerWithConsumer:(id<FBFileConsumer>)consumer;

/**
 Await for the Consumer to finish consuming the input.

 @param timeout the timeout to wait in seconds.
 @param error an error out if the timeout is reached.
 @return YES if successful, NO otherwise.
 */
- (BOOL)awaitEndOfFileWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Whether the Consumer has consumed the EOF.
 */
@property (atomic, assign, readonly) BOOL hasConsumedEOF;

@end

/**
 A Reader of Text Data, calling the callback when a full line is available.
 */
@interface FBLineFileConsumer : NSObject <FBFileConsumer>

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

@end

/**
 A Reader that accumilates data.
 */
@interface FBAccumilatingFileConsumer : NSObject <FBFileConsumer>

/**
 Initializes the reader with empty data.

 @return a new Data Reader.
 */
- (instancetype)init;

/**
 Initializes the reader with provided data.

 @param data the data to append to.
 @return a new Data Reader.
 */
- (instancetype)initWithMutableData:(NSMutableData *)data;

/**
 Obtains a copy of the current output data.
 */
@property (atomic, copy, readonly) NSData *data;

@end

/**
 A Composite Consumer.
 */
@interface FBCompositeFileConsumer : NSObject <FBFileConsumer>

/**
 A Consumer of Consumers.

 @param consumers the consumers to compose.
 @return a new consumer.
 */
+ (instancetype)consumerWithConsumers:(NSArray<id<FBFileConsumer>> *)consumers;

@end

NS_ASSUME_NONNULL_END
