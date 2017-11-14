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
+ (FBFuture<T> *)futureWithError:(NSError *)error;

/**
 Construct a Future that resolves with a delay.

 @param delay the delay to resolve the future in.
 @param future the future to resolve
 @return the Future wrapped in a delay.
 */
+ (FBFuture<T> *)futureWithDelay:(NSTimeInterval)delay future:(FBFuture<T> *)future;

/**
 Constructs a Future that resolves successfully when the resolveWhen block returns YES.

 @param queue to resolve on.
 @param resolveWhen a block determining when the future should resolve.
 @return a new Future that resolves when the resolution block returns YES.
 */
+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue resolveWhen:(BOOL (^)(void))resolveWhen;

/**
 Constructs a Future that resolves successfully when the resolveUntil block resolves a Future that resolves a value.
 Each resolution will occur one-after-another.

 @param queue to resolve on.
 @param resolveUntil a block that returns a future to resolve.
 @return a new Future that resolves when the future returned by the block resolves a value.
 */
+ (FBFuture<T> *)onQueue:(dispatch_queue_t)queue resolveUntil:(FBFuture<T> *(^)(void))resolveUntil;

/**
 Resolve a future asynchronously, by value.

 @param queue to resolve on.
 @param resolve the the block to resolve the future.
 @return the reciever, for chaining.
 */
+ (instancetype)onQueue:(dispatch_queue_t)queue resolveValue:( T(^)(NSError **) )resolve;

/**
 Resolve a future asynchronously, by returning a future.

 @param queue to resolve on.
 @param resolve the the block to resolve the future.
 @return the reciever, for chaining.
 */
+ (instancetype)onQueue:(dispatch_queue_t)queue resolve:( FBFuture *(^)(void) )resolve;

/**
 Constructs a Future from an Array of Futures.
 The future will resolve when all futures in the array have resolved.
 If any future results in an error, the first one will be progated and results of succeful

 @param futures the futures to compose.
 @return a new Future with the resolved results of all the composed futures.
 */
+ (FBFuture<NSArray<T> *> *)futureWithFutures:(NSArray<FBFuture<T> *> *)futures;

/**
 Constructrs a Future from an Array of Futures.
 The future which resolves the first will be returned.
 All other futures will be cancelled.

 @param futures the futures to compose.
 @return a new Future with the first future that resolves.
 */
+ (FBFuture<T> *)race:(NSArray<FBFuture<T> *> *)futures NS_SWIFT_NAME(init(race:));

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
- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCompletion:(void (^)(FBFuture *))handler;

/**
 Notifies of Cancellation.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Reciever, for chaining.
 */
- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCancellation:(void (^)(FBFuture *))handler;

/**
 Chain Futures based on any non-cancellation resolution of the reciever.
 Cancellation will be instantly propogated.

 @param queue the queue to chain on.
 @param chain the chaining handler, called on all completion events.
 @return a chained future
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture * (^)(FBFuture *future))chain;

/**
 FlatMap a successful resolution of the reciever to a new Future.

 @param queue the queue to chain on.
 @param fmap the function to re-map the result to a new future, only called on success.
 @return a flatmapped future
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture * (^)(T result))fmap;

/**
 Map a future's result to a new value, based on a successful resolution of the reciever.

 @param queue the queue to map on.
 @param map the mapping block, only called on success.
 @return a mapped future
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(T result))map;

/**
 Cancels the receiver if it doesn't resolve within the timeout.

 @param timeout to use.
 @return a new future.
 */
- (FBFuture *)timedOutIn:(NSTimeInterval)timeout;

/**
 Replaces the value on a successful future.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (FBFuture *)mapReplace:(id)replacement;

/**
 Once the reciever has resolved, resolves with a second future.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (FBFuture *)fmapReplace:(FBFuture *)replacement;

/**
 Shields the future from failure, replacing it with the provided value.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (FBFuture<T> *)fallback:(T)replacement;

/**
 Delays delivery of the completion of the reciever.
 A chaining convenience over -[FBFuture futureWithDelay:future:]

 @param delay the delay to resolve the future in.
 @return a delayed future.
 */
- (FBFuture<T> *)delay:(NSTimeInterval)delay;

/**
 Replaces the error message in the event of a failure.

 @param format the format string to re-phrase the failure message.
 @return a future with the replacement.
 */
- (FBFuture *)rephraseFailure:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

#pragma mark Properties

/**
 YES if reciever has terminated, NO otherwise.
 */
@property (atomic, assign, readonly) BOOL hasCompleted;

/**
 The Error if one is present.
 */
@property (nonatomic, copy, nullable, readonly) NSError *error;

/**
 The Result.
 */
@property (nonatomic, copy, nullable, readonly) T result;

/**
 The State.
 */
@property (nonatomic, assign, readonly) FBFutureState state;

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
