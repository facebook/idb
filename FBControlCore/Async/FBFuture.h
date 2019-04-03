/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
 Resolve a future synchronously, by value.

 @param resolve the the block to resolve the future.
 @return the reciever, for chaining.
 */
+ (instancetype)resolveValue:( T(^)(NSError **) )resolve;

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

#pragma mark Cancellation

/**
 Cancels the asynchronous operation.
 This will always start the process of cancellation.
 Some cancellation is immediate, the returned future may resolve immediatey.

 However, other cancellation operations are asynchronous, where the future will not resolve immediately.
 If you wish to wait for the cancellation to have been fully resolved, chain on the future returned.

 @return a Future that resolves when cancellation of all handlers has been processed.
 */
- (FBFuture<NSNull *> *)cancel;

/**
 Removes existing cancellation propogation.
 Deriving new futures will propogate cancellation within the chain.
 However, this may be undesirable if you wish to prevent a default cancellation from propogating.
 This is useful when you wish to override the default cancellation behaviour of chained futures.

 @return the reciever, for chaining.
 */
- (instancetype)shieldCancellation;

/**
 Respond to the cancellation of the reciever.
 Since the cancellation handler can itself return a future, asynchronous cancellation is permitted.
 This can be called multiple times for the same Future if multiple cleanup operations need to occur.

 Make sure that the future that is returned from this block is itself not the same reference as the reciever.
 Otherwise the `cancel` call will itself resolve as 'cancelled'.

 @param queue the queue to notify on.
 @param handler the block to invoke if cancelled.
 @return the Reciever, for chaining.
 */
- (instancetype)onQueue:(dispatch_queue_t)queue respondToCancellation:(FBFuture<NSNull *> *(^)(void))handler;

#pragma mark Completion Notification

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

#pragma mark Deriving new Futures

/**
 Chain Futures based on any non-cancellation resolution of the reciever.
 All completion events are called in the chained future block (Done, Error, Cancelled).

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

#pragma mark Creating Context

/**
 Creates an 'context object' that allows for the value contained by a future to be torn-down when the context is done.
 This is useful for resource cleanup, where closing a resource needs to be managed.
 The teardown will always be called, regardless of the terminating condition of any chained future.
 The state passed in the teardown callback is the state of the resolved future from any chaining that may happen.
 The teardown will only be called if the reciever has resolved, as this is how the context value is resolved.

 @param queue the queue to perform the teardown on.
 @param action the teardown action to invoke. This block will be executed after the context object is done. This also includes the state that the resultant future ended in.
 @return a 'context object' that manages the tear-down of the reciever's value.
 */
- (FBFutureContext<T> *)onQueue:(dispatch_queue_t)queue contextualTeardown:(void(^)(T, FBFutureState))action;

/**
 Creates an 'context object' from a block.

 @param queue the queue to perform the teardown on.
 @param fmap the 'context object' to add.
 @return a 'contex object' that manages the tear-down of the reciever's value.
 */
- (FBFutureContext *)onQueue:(dispatch_queue_t)queue pushTeardown:(FBFutureContext *(^)(T))fmap;

#pragma mark Metadata

/**
 Rename the future.

 @param name the name of the Future.
 @return the reciever, for chaining.
 */
- (FBFuture<T> *)named:(NSString *)name;

/**
 Rename the future with a format string.

 @param format the format string for the Future's name.
 @return the reciever, for chaining.
 */
- (FBFuture<T> *)nameFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 A helper to log completion of the future.

 @param logger the logger to log to.
 @param format a description of the future.
 @return the reciever, for chaining
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

/**
 The name of the Future.
 This can be used to set contextual information about the work that the Future represents.
 Any name is incorporated into the description.
 */
@property (atomic, copy, nullable, readonly) NSString *name;

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
+ (FBMutableFuture<T> *)future;

/**
 A Mutable Future with a Name.

 @param name the name of the Future
 @return a new Mutable Future.
 */
+ (FBMutableFuture<T> *)futureWithName:(nullable NSString *)name;

/**
 A Mutable Future with a Formatted Name

 @param format the format string for the Future's name.
 @return a new Mutable Future.
 */
+ (FBMutableFuture<T> *)futureWithNameFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

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

#pragma mark Initializers

/**
 Constructs a context with no teardown.

 @param future the future to wrap.
 @return a FBFutureContext wrapping the Future.
 */
+ (FBFutureContext<T> *)futureContextWithFuture:(FBFuture<T> *)future;

/**
 Constructs a context with no teardown, from a result.

 @param result the result to wrap.
 @return a FBFutureContext wrapping the Future.
 */
+ (FBFutureContext<T> *)futureContextWithResult:(T)result;

/**
 Constructs a context with no teardown, from an error.

 @param error an error to raise.
 @return a new Future Context.
 */
+ (FBFutureContext *)futureContextWithError:(NSError *)error;

#pragma mark Public Methods

/**
 Return a Future from the context.
 The reciever's teardown will occur *after* the Future returned by `pop` resolves.
 If you wish to keep the context alive after the `pop` then use `pend` instead.

 @param queue the queue to chain on.
 @param pop the function to re-map the result to a new future, only called on success.
 @return a Future derived from the fmap. The teardown of the context will occur *after* this future has resolved.
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue pop:(FBFuture * (^)(T result))pop;

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
 Adds a teardown to the context

 @param queue the queue to call the teardown on
 @param action the teardown action
 @return a context with the teardown applied.
 */
- (FBFutureContext *)onQueue:(dispatch_queue_t)queue contextualTeardown:(void(^)(T, FBFutureState))action;

/**
 Extracts the wrapped context, so that it can be torn-down at a later time.
 This is designed to allow a context manager to be combined with the teardown of other long-running operations.

 @param queue the queue to chain on.
 @param enter the block that recieves two parameters. The first is the context value, the second is a future that will tear-down the context when it is resolved.
 @return a Future that wraps the value returned from fmap.
 */
- (FBFuture *)onQueue:(dispatch_queue_t)queue enter:(id (^)(T result, FBMutableFuture<NSNull *> *teardown))enter;

#pragma mark Properties

/**
 The future keeping the context alive.
 The context will not be torn down until this future resolves.
 */
@property (nonatomic, strong, readonly) FBFuture<T> *future;

@end

NS_ASSUME_NONNULL_END
