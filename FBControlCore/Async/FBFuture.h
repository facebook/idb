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
 A State for the Future.
 */
typedef NS_ENUM(NSUInteger, FBFutureState) {
  FBFutureStateRunning,
  FBFutureStateCompletedWithResult,
  FBFutureStateCompletedWithError,
  FBFutureStateCompletedWithCancellation,
};

/**
 A String Mirror of the State.
 */
typedef NSString *FBFutureStateString NS_STRING_ENUM;

extern FBFutureStateString const FBFutureStateStringRunning;
extern FBFutureStateString const FBFutureStateStringCompletedWithResult;
extern FBFutureStateString const FBFutureStateStringCompletedWithError;
extern FBFutureStateString const FBFutureStateStringWithCancellation;

/**
 Make a State String from the State.
 */
FBFutureStateString FBFutureStateStringFromState(FBFutureState state);

/**
 A Future Operation
 */
@interface FBFuture <T : id> : NSObject

#pragma mark Initializers

/**
 Constructs a Future that wraps a result

 @param result the result.
 @return a new Future.
 */
+ (FBFuture<T> *)futureWithResult:(T)result;

/**
 Constructs a Future that wraps an error.

 @param error the error to wrap.
 @return a new Future.
 */
+ (FBFuture *)futureWithError:(NSError *)error;

/**
 Constructs a Future from an Array of Futures.
 The future will resolve when all futures in the array have resolved.
 If any future results in an error, the first one will be progated and results of succeful

 @param futures the futures to compose.
 @return a new Future
 */
+ (FBFuture<T> *)futureWithFutures:(NSArray<FBFuture<T> *> *)futures;

#pragma mark Public Methods

/**
 Cancels the asynchronous operation.

 @return the Reciever, for chaining.
 */
- (instancetype)cancel;

/**
 Notifies of Completion.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Reciever, for chaining.
 */
- (instancetype)notifyOfCompletionOnQueue:(dispatch_queue_t)queue handler:(void (^)(FBFuture *))handler;

/**
 Chain Futures based on the result.

 @param queue the queue to chain on.
 @param chain the chaining handler.
 @return a chained future
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture * (^)(T result))chain;

/**
 Map a future's result to a new value

 @param queue the queue to map on.
 @param map the mapping block.
 @return a mapped future
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(T result))map;

#pragma mark Properties

/**
 YES if reciever has terminated, NO otherwise.
 */
@property (atomic, assign, readonly) BOOL hasCompleted;

/**
 The Error if one is present.
 */
@property (atomic, copy, nullable, readonly) NSError *error;

/**
 The Result.
 */
@property (atomic, copy, nullable, readonly) T result;

/**
 The State.
 */
@property (atomic, assign, readonly) FBFutureState state;

@end

/**
 A Future that can be modified.
 */
@interface FBMutableFuture <T : id> : FBFuture

#pragma mark Initializers

/**
 A Future that can be controlled externally.
 */
+ (FBMutableFuture<T> *)future;

#pragma mark Mutation

/**
 Make the wrapped future succeeded.

 @param result The result.
 @return the reciever, for chaining.
 */
- (instancetype)resolveWithResult:(T)result;

/**
 Make the wrapped future fail with an error.

 @param error The error.
 @return the reciever, for chaining.
 */
- (instancetype)resolveWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
