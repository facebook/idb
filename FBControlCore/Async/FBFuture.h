/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 A State for the Future.
 */
typedef NS_ENUM(NSUInteger, FBFutureState) {
  FBFutureStateRunning = 1,  /* The Future hasn't resolved yet */
  FBFutureStateDone = 2,  /* The Future has resolved successfully */
  FBFutureStateFailed = 3,  /* The Future has resolved in error */
  FBFutureStateCancelled = 4,  /* The Future has been cancelled */
};

extern dispatch_time_t FBCreateDispatchTimeFromDuration(NSTimeInterval inDuration);

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
+ (nonnull FBFuture<T> *)futureWithResult:(nullable T)result;

/**
 Constructs a Future that wraps an error.

 @param error the error to wrap.
 @return a new Future.
 */
+ (nonnull FBFuture<T> *)futureWithError:(nullable NSError *)error;

/**
 Construct a Future that resolves with a delay.

 @param delay the delay to resolve the future in.
 @param future the future to resolve
 @return the Future wrapped in a delay.
 */
+ (nonnull FBFuture<T> *)futureWithDelay:(NSTimeInterval)delay future:(nonnull FBFuture<T> *)future;

/**
 Resolve a future asynchronously, by returning a future.

 @param queue to resolve on.
 @param resolve the block to resolve the future.
 @return a new Future.
 */
+ (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue resolve:(nonnull FBFuture * _Nonnull (^)(void))resolve;

/**
 Constructs a future from an array of futures.
 The future will resolve when all futures in the array have resolved.
 If any future resolves in an error, the first error will be propagated. Any pending futures will not be cancelled.
 If any future resolves in cancellation, the cancellation will be propagated. Any pending futures will not be cancelled.

 @param futures the futures to compose.
 @return a new future with the resolved results of all the composed futures.
 */
+ (nonnull FBFuture<NSArray<T> *> *)futureWithFutures:(nonnull NSArray<FBFuture<T> *> *)futures NS_SWIFT_NAME(combine(_:));

/**
 Constructs a Future from an Array of Futures.
 The future which resolves the first will be returned.
 All other futures will be cancelled.

 @param futures the futures to compose.
 @return a new Future with the first future that resolves.
 */
+ (nonnull FBFuture<T> *)race:(nonnull NSArray<FBFuture<T> *> *)futures NS_SWIFT_NAME(init(race:));

/**
 A resolved future, with an insignificant value.
 This can be used to communicate "success", where an errored future would indicate failure.

 @return a new Future that's resolved with an NSNull value.
 */
+ (nonnull FBFuture<NSNull *> *)empty;

#pragma mark Cancellation

/**
 Cancels the asynchronous operation.
 This will always start the process of cancellation.
 Some cancellation is immediate, the returned future may resolve immediately.

 However, other cancellation operations are asynchronous, where the future will not resolve immediately.
 If you wish to wait for the cancellation to have been fully resolved, chain on the future returned.

 @return a Future that resolves when cancellation of all handlers has been processed.
 */
- (nonnull FBFuture<NSNull *> *)cancel;

/**
 Respond to the cancellation of the receiver.
 Since the cancellation handler can itself return a future, asynchronous cancellation is permitted.
 This can be called multiple times for the same Future if multiple cleanup operations need to occur.

 Make sure that the future that is returned from this block is itself not the same reference as the receiver.
 Otherwise the `cancel` call will itself resolve as 'cancelled'.

 @param queue the queue to notify on.
 @param handler the block to invoke if cancelled.
 @return the Receiver, for chaining.
 */
- (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue respondToCancellation:(nonnull FBFuture<NSNull *> * _Nonnull (^)(void))handler;

#pragma mark Completion Notification

/**
 Notifies of the resolution of the Future.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Receiver, for chaining.
 */
- (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue notifyOfCompletion:(nonnull void (^)(FBFuture * _Nonnull))handler;

#pragma mark Deriving new Futures

/**
 Chains on every terminal state of the receiver (Done, Error, Cancelled).

 @param queue the queue to chain on.
 @param chain the chaining handler, called on all completion events.
 @return a chained future
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue chain:(nonnull FBFuture * _Nonnull (^)(FBFuture * _Nonnull future))chain;

/**
 FlatMap a successful resolution of the receiver to a new Future.

 @param queue the queue to chain on.
 @param fmap the function to re-map the result to a new future, only called on success.
 @return a flatmapped future
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue fmap:(nonnull FBFuture * _Nonnull (^)(T _Nonnull result))fmap;

/**
 Map a future's result to a new value, based on a successful resolution of the receiver.

 @param queue the queue to map on.
 @param map the mapping block, only called on success.
 @return a mapped future
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue map:(nonnull id _Nonnull (^)(T _Nonnull result))map;

/**
 Returns a copy of this future that'll resolve on a specific queue

 @param queue the queue to resolve on
 @return a copy of this future that'll resolve on the specified queue
 */
- (nonnull FBFuture<T> *)onQueue:(nonnull dispatch_queue_t)queue;

/**
 Attempt to handle an error.

 @param queue the queue to handle on.
 @param handler the block to invoke.
 @return a Future that will attempt to handle the error
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue handleError:(nonnull FBFuture * _Nonnull (^)(NSError * _Nonnull))handler;

/**
 Cancels the receiver if it doesn't resolve within the timeout.
 The chained future is resolved in error, with the provided error message.

 @param timeout the amount of time to time out the receiver in
 @param description the description of the timeout.
 @return the current future with a timeout applied.
 */
- (nonnull FBFuture *)timeout:(NSTimeInterval)timeout waitingFor:(nonnull NSString *)description;

/**
 Cancels the receiver if it doesn't resolve within the timeout.
 The chained future is resolved based upon the value returned within the handler.

 @param queue the queue to call the handler on.
 @param timeout the amount of time to time out the receiver in
 @param handler the block that will be fired on timeout.
 @return the current future with a timeout applied.
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue timeout:(NSTimeInterval)timeout handler:(nonnull FBFuture * _Nonnull (^)(void))handler;

/**
 Replaces the value on a successful future.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (nonnull FBFuture *)mapReplace:(nonnull id)replacement;

/**
 Shields the future from failure, replacing it with the provided value.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (nonnull FBFuture<T> *)fallback:(nonnull T)replacement;

/**
 Delays delivery of the completion of the receiver.
 A chaining convenience over -[FBFuture futureWithDelay:future:]

 @param delay the delay to resolve the future in.
 @return a delayed future.
 */
- (nonnull FBFuture<T> *)delay:(NSTimeInterval)delay;

#pragma mark Creating Context

#pragma mark Metadata

/**
 Rename the future.

 @param name the name of the Future.
 @return the receiver, for chaining.
 */
- (nonnull FBFuture<T> *)named:(nonnull NSString *)name;

#pragma mark Properties

/**
 YES if receiver has terminated, NO otherwise.
 */
@property (atomic, readonly, assign) BOOL hasCompleted;

/**
 The Error if one is present.
 */
@property (nullable, atomic, readonly, copy) NSError *error;

/**
 The Result.
 */
@property (nullable, atomic, readonly, copy) T result;

/**
 The State.
 */
@property (atomic, readonly, assign) FBFutureState state;

/**
 The name of the Future.
 This can be used to set contextual information about the work that the Future represents.
 Any name is incorporated into the description.
 */
@property (nullable, atomic, readonly, copy) NSString *name;

@end

/**
 A Future that can be modified.
 */
@interface FBMutableFuture <T : id> : FBFuture

#pragma mark Initializers

/**
 A Future that can be controlled externally.
 The Future is in a 'running' state until it is resolved with the `resolve` methods.

 @return a new Mutable Future.
 */
+ (nonnull FBMutableFuture<T> *)future;

/**
 A Mutable Future with a Name.

 @param name the name of the Future
 @return a new Mutable Future.
 */
+ (nonnull FBMutableFuture<T> *)futureWithName:(nullable NSString *)name;

#pragma mark Mutation

/**
 Make the wrapped future succeeded.

 @param result The result.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)resolveWithResult:(nullable T)result;

/**
 Make the wrapped future fail with an error.

 @param error The error.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)resolveWithError:(nullable NSError *)error;

/**
 Resolve the receiver upon the completion of another future.

 @param future the future to resolve from.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)resolveFromFuture:(nonnull FBFuture *)future;

@end
