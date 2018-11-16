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

@class FBFutureContext<T>;

@protocol FBControlCoreLogger;

/**
 A State for the Future.
 */
typedef NS_ENUM(NSUInteger, FBFutureState) {
  FBFutureStateRunning = 1,  /* The Future hasn't resolved yet */
  FBFutureStateDone = 2,  /* The Future has resolved successfully */
  FBFutureStateFailed = 3,  /* The Future has resolved in error */
  FBFutureStateCancelled = 4,  /* The Future has been cancelled */
};

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
 This will always start the process of cancellation.
 Some cancellation is immediate, however there are some cases where cancellation is asynchronous.
 In these cases the future returned will not be resolved immediately.
 If you wish to wait for the cancellation to have been fully resolved, chain on the future returned.

 @return a Future that resolves when cancellation of all handlers has been processed.
 */
- (FBFuture<NSNull *> *)cancel;

/**
 Notifies of the resolution of the Future.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Reciever, for chaining.
 */
- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCompletion:(void (^)(FBFuture *))handler;

/**
 Notifies of the successful resolution of the Future.
 The handler will resolve before the chained Future.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Reciever, for chaining.
 */
- (instancetype)onQueue:(dispatch_queue_t)queue doOnResolved:(void (^)(T))handler;

/**
 Respond to a cancellation request.
 This provides the opportunity to provide asynchronous cancellation.
 This can be called multiple times for the same reference.

 @param queue the queue to notify on.
 @param handler the block to invoke if cancelled.
 @return the Reciever, for chaining.
 */
- (instancetype)onQueue:(dispatch_queue_t)queue respondToCancellation:(FBFuture<NSNull *> *(^)(void))handler;

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
 Attempt to handle an error.

 @param queue the queue to handle on.
 @param handler the block to invoke.
 @return a Future that will attempt to handle the error
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue handleError:(FBFuture * (^)(NSError *))handler;

/**
 Creates an FBFutureContext that allows the value yielded from the future to be torn down.

 @param queue the queue to perform the teardown on.
 @param action the teardown action to invoke
 @return an object that acts as a proxy to the teardown.
 */
- (FBFutureContext<T> *)onQueue:(dispatch_queue_t)queue contextualTeardown:(void(^)(T))action;

/**
 Creates an FBFutureContext that allows a future to be mapped into a FBFutureContext.

 @param queue the queue to perform the teardown on.
 @param fmap the teardown to push
 @return an object that acts as a proxy to the teardown.
 */
- (FBFutureContext *)onQueue:(dispatch_queue_t)queue pushTeardown:(FBFutureContext *(^)(T))fmap;

/**
 Cancels the receiver if it doesn't resolve within the timeout.

 @param timeout the amount of time to time out the receiver in
 @param format the description of the timeout
 @return the current future with a timeout applied.
 */
- (FBFuture *)timeout:(NSTimeInterval)timeout waitingFor:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

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
- (FBFuture<T> *)rephraseFailure:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 A helper to log completion of the future.

 @param logger the logger to log to.
 @param format a description of the future.
 */
- (FBFuture<T> *)logCompletion:(id<FBControlCoreLogger>)logger withPurpose:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

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

/**
 Resolve the reciever upon the completion of another future.

 @param future the future to resolve from.
 @return the reciever, for chaining.
 */
- (instancetype)resolveFromFuture:(FBFuture *)future;

@end

/**
 Wraps a Future in such a way that teardown work can be deferred.
 This is useful when the Future wraps some kind of resource that requires cleanup.
 The completion of some chained future is used as the trigger to determine that cleanup should be performed.

 From this class:
 - A Future can be obtained that will completed before the teardown work does.
 - Additional chaining is possible, deferring the teardown further.

 The API intentionally mirrors some of the methods in FBFuture.
 The Nominal types are different so that it is impossible to get FBFuture and FBFutureContext mixed up.
 */
@interface FBFutureContext <T : id> : NSObject

#pragma mark Public Methods

/**
 Return a Future from the context.
 The reciever's teardown will occur *after* the Future returned by `fmap` resolves.

 @param queue the queue to chain on.
 @param fmap the function to re-map the result to a new future, only called on success.
 @return a Future derived from the fmap. The teardown of the context will occur *after* this future has resolved.
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture * (^)(T result))fmap;

/**
 Continue to keep the context alive, but fmap a new future.
 The reciever's teardown will not occur after the `pend`'s Future has resolved.

 @param queue the queue to chain on.
 @param fmap the function to re-map the result to a new future, only called on success.
 @return a Context derived from the fmap.
 */
- (FBFutureContext *)onQueue:(dispatch_queue_t)queue pend:(FBFuture * (^)(T result))fmap;

/**
 Pushes another context.
 This can be used to make a stack of contexts that unroll once the produced context pops.

 @param queue the queue to chain on.
 @param fmap the block to produce more context.
 @return a Context derived from the fmap with the current context stacked below.
 */
- (FBFutureContext *)onQueue:(dispatch_queue_t)queue push:(FBFutureContext * (^)(T result))fmap;

/**
 An empty context that raises an error.

 @param error an error to raise.
 @return a new Future Context.
 */
+ (FBFutureContext *)error:(NSError *)error;

#pragma mark Properties

/**
 The future keeping the context alive.
 The context will not be torn down until this future resolves.
 */
@property (nonatomic, strong, readonly) FBFuture<T> *future;

@end

NS_ASSUME_NONNULL_END
