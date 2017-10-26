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

@protocol FBFileConsumer;

/**
 A class that provided a writable file handle attached to a consumer.
 */
@interface FBPipeReader : NSObject

#pragma mark Initializers

/**
 A Pipe Reader with the writable end attached to the consumer.

 @param consumer the Consumer to Write to.
 @return a Pipe Reader.
 */
+ (instancetype)pipeReaderWithConsumer:(id<FBFileConsumer>)consumer;

#pragma mark Properties

/**
 The Pipe the consumer is attached to.
 Users of the class may write to the writable end.
 */
@property (nonatomic, strong, readonly) NSPipe *pipe;

#pragma mark Public Methods

/**
 Starts the Consumption of the Pipe

 @param error an error out for any error that occurs.
 @return YES if the reading started normally, NO otherwise.
 */
- (BOOL)startReadingWithError:(NSError **)error;

/**
 Stops reading the Pipe.

 @return a Future when all of the work has been drained.
 */
- (FBFuture<NSNull *> *)stopReading;

/**
 Stops the Consumption of the Pipe.

 @param error an error out for any error that occurs.
 @return YES if the reading terminated normally, NO otherwise.
 */
- (BOOL)stopReadingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
