/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
 Loop status for onQueue:resolveOrFailWhen:
 */
typedef NS_ENUM(NSUInteger, FBFutureLoopState) {
  FBFutureLoopContinue = 1,  /* FBFuture resolveOrFailWhen will continue */
  FBFutureLoopFinished = 2,  /* FBFuture resolveOrFailWhen has finished */
  FBFutureLoopFailed = 3,  /* FBFuture resolveOrFailWhen has failed */
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
+ (nonnull FBFuture<T> *)futureWithResult:(nonnull T)result;

/**
 Constructs a Future that wraps an error.

 @param error the error to wrap.
 @return a new Future.
 */
+ (nonnull FBFuture<T> *)futureWithError:(nonnull NSError *)error;

/**
 Construct a Future that resolves with a delay.

 @param delay the delay to resolve the future in.
 @param future the future to resolve
 @return the Future wrapped in a delay.
 */
+ (nonnull FBFuture<T> *)futureWithDelay:(NSTimeInterval)delay future:(nonnull FBFuture<T> *)future;

/**
 Constructs a Future that resolves successfully when the resolveWhen block returns YES.
 onQueue:resolveWhen: is a shortcut to onQueue:resolveOrFailWhen:

 @param queue to resolve on.
 @param resolveWhen a block determining when the future should resolve.
 @return a new Future that resolves when the resolution block returns YES.
 */
+ (nonnull FBFuture<NSNull *> *)onQueue:(nonnull dispatch_queue_t)queue resolveWhen:(nonnull BOOL (^)(void))resolveWhen;

/**
 Constructs a Future that resolves when the resolveOrFailWhen block returns FBFutureLoopState.
 resolveOrFailWhen block will be executed every 100ms to determine when the future should be resolved:

  * If resolveOrFailWhen block returns FBFutureLoopContinue, the future will continue in Running state
  * If resolveOrFailWhen block returns FBFutureLoopFinished and errorOut is not set, the future will resolve successfully
  * If resolveOrFailWhen block returns FBFutureLoopFailed and error out is set, the future will resolve on a failure.

 @param queue to resolve on.
 @param resolveOrFailWhen a block determining when the future should resolve. Future will resolve into a failure if `errorOut` is not nil.
 @return a new Future that resolves when the resolution block returns FBFutureLoopFinished or FBFutureLoopFailed.
 */
+ (nonnull FBFuture<NSNull *> *)onQueue:(nonnull dispatch_queue_t)queue resolveOrFailWhen:(nonnull FBFutureLoopState (^)(NSError * _Nullable * _Nullable errorOut))resolveOrFailWhen;

/**
 Constructs a Future that resolves successfully when the resolveUntil block resolves a Future that resolves a value.
 Each resolution will occur one-after-another.

 @param queue to resolve on.
 @param resolveUntil a block that returns a future to resolve.
 @return a new Future that resolves when the future returned by the block resolves a value.
 */
+ (nonnull FBFuture<T> *)onQueue:(nonnull dispatch_queue_t)queue resolveUntil:(nonnull FBFuture<T> * _Nonnull (^)(void))resolveUntil;

/**
 Resolve a future synchronously, by value.

 @param resolve the the block to resolve the future.
 @return the receiver, for chaining.
 */
+ (nonnull instancetype)resolveValue:(nonnull T _Nullable (^)(NSError * _Nullable * _Nullable))resolve;

/**
 Resolve a future asynchronously, by value.

 @param queue to resolve on.
 @param resolve the the block to resolve the future.
 @return the receiver, for chaining.
 */
+ (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue resolveValue:(nonnull T _Nullable (^)(NSError * _Nullable * _Nullable))resolve;

/**
 Resolve a future asynchronously, by returning a future.

 @param queue to resolve on.
 @param resolve the the block to resolve the future.
 @return the receiver, for chaining.
 */
+ (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue resolve:(nonnull FBFuture * _Nonnull (^)(void))resolve;

/**
 Constructs a future from an array of futures.
 The future will resolve when all futures in the array have resolved.
 If any future resolves in an error, the first error will be propogated. Any pending futures will not be cancelled.
 If any future resolves in cancellation, the cancellation will be propogated. Any pending futures will not be cancelled.

 @param futures the futures to compose.
 @return a new future with the resolved results of all the composed futures.
 */
+ (nonnull FBFuture<NSArray<T> *> *)futureWithFutures:(nonnull NSArray<FBFuture<T> *> *)futures NS_SWIFT_NAME(combine(_:));

/**
 Constructrs a Future from an Array of Futures.
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
 Some cancellation is immediate, the returned future may resolve immediatey.

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

/**
 Notifies of the successful resolution of the Future.
 The handler will resolve before the chained Future.

 @param queue the queue to notify on.
 @param handler the block to invoke.
 @return the Receiver, for chaining.
 */
- (nonnull instancetype)onQueue:(nonnull dispatch_queue_t)queue doOnResolved:(nonnull void (^)(T _Nonnull))handler;

#pragma mark Deriving new Futures

/**
 Chain Futures based on any non-cancellation resolution of the receiver.
 All completion events are called in the chained future block (Done, Error, Cancelled).

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
 @returns a copy of this future that'll resolve on the specified queue
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
 Once the receiver has resolved in any state, chains to another Future.
 This is un-conditional, if the receiver resolves in error the replacement will still be used.

 @param replacement the replacement
 @return a future with the replacement.
 */
- (nonnull FBFuture *)chainReplace:(nonnull FBFuture *)replacement;

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

/**
 Replaces the error message in the event of a failure.

 @param description the description to re-phrase the failure message.
 @return a future with the replacement.
 */
- (nonnull FBFuture<T> *)rephraseFailure:(nonnull NSString *)description;

#pragma mark Creating Context

/**
 Creates an 'context object' that allows for the value contained by a future to be torn-down when the context is done.
 This is useful for resource cleanup, where closing a resource needs to be managed.
 The teardown will always be called, regardless of the terminating condition of any chained future.
 The state passed in the teardown callback is the state of the resolved future from any chaining that may happen.
 The teardown will only be called if the receiver has resolved, as this is how the context value is resolved.

 @param queue the queue to perform the teardown on.
 @param action the teardown action to invoke. This block will be executed after the context object is done. This also includes the state that the resultant future ended in.
 @return a 'context object' that manages the tear-down of the receiver's value. This teardown can be asynchronous, and is indicated via the return-value of the contextualTeardown block,
 */
- (nonnull FBFutureContext<T> *)onQueue:(nonnull dispatch_queue_t)queue contextualTeardown:(nonnull FBFuture<NSNull *> * _Nonnull (^)(T _Nonnull, FBFutureState))action;

/**
 Creates an 'context object' from a block.

 @param queue the queue to perform the teardown on.
 @param fmap the 'context object' to add.
 @return a 'contex object' that manages the tear-down of the receiver's value.
 */
- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue pushTeardown:(nonnull FBFutureContext * _Nonnull (^)(T _Nonnull))fmap;

#pragma mark Metadata

/**
 Rename the future.

 @param name the name of the Future.
 @return the receiver, for chaining.
 */
- (nonnull FBFuture<T> *)named:(nonnull NSString *)name;

/**
 A helper to log completion of the future.

 @param logger the logger to log to.
 @param purpose a description of the future.
 @return the receiver, for chaining
 */
- (nonnull FBFuture<T> *)logCompletion:(nonnull id<FBControlCoreLogger>)logger withPurpose:(nonnull NSString *)purpose;

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
- (nonnull instancetype)resolveWithResult:(nonnull T)result;

/**
 Make the wrapped future fail with an error.

 @param error The error.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)resolveWithError:(nonnull NSError *)error;

/**
 Resolve the receiver upon the completion of another future.

 @param future the future to resolve from.
 @return the receiver, for chaining.
 */
- (nonnull instancetype)resolveFromFuture:(nonnull FBFuture *)future;

@end

/**
 Wraps a Future in such a way that teardown work can be deferred.
 This is useful when the Future wraps some kind of resource that requires cleanup.
 Upon completion of the future that the context wraps, a teardown action associated with the context is then performed.

 From this class:
 - A Future can be obtained that will completed before the teardown work does.
 - Additional chaining is possible, deferring teardown, or adding to a stack of teardowns.

 The API intentionally mirrors some of the methods in FBFuture, so that it can used in equivalent places.
 The nominal types of FBFuture and FBFutureContext so that it hard to confuse chaining on between them.

 Like cancellation on a Future, teardown is also permitted to be asynchronous. This is important where resources are allocated on top of each other.
 For example this can be useful to have set-up and tear-down actions performed in the order they are added to the teardown stack:
 1) A socket is created.
 2) A file read operation is made on the socket.
 3) The file read operation is used, and then finishes.
 4) The file read operation is stopped.
 5) The socket is closed.

 In this case it's important that #4 has finished it's teardown work before #5 completes.
 This is achieved by a teardown action returning a future that completes when the work of #4 is completely done.
 Async teardown is completely optional, if the ordering is not significant, then the action can return an empty future to not defer any teardown work lower in the stack.
 */
@interface FBFutureContext <T : id> : NSObject

#pragma mark Initializers

/**
 Constructs a context with no teardown.

 @param future the future to wrap.
 @return a FBFutureContext wrapping the Future.
 */
+ (nonnull FBFutureContext<T> *)futureContextWithFuture:(nonnull FBFuture<T> *)future;

/**
 Constructs a context with no teardown, from a result.

 @param result the result to wrap.
 @return a FBFutureContext wrapping the Future.
 */
+ (nonnull FBFutureContext<T> *)futureContextWithResult:(nonnull T)result;

/**
 Constructs a context with no teardown, from an error.

 @param error an error to raise.
 @return a new Future Context.
 */
+ (nonnull FBFutureContext *)futureContextWithError:(nonnull NSError *)error;

/**
 Constructs a FBFutureContext in Parallel.

 @param contexts the contexts to use.
 @return a new FBFutureContext with the underlying contexts in an array.
 */
+ (nonnull FBFutureContext<NSArray<id> *> *)futureContextWithFutureContexts:(nonnull NSArray<FBFutureContext *> *)contexts;

#pragma mark Public Methods

/**
 Return a Future from the context.
 The receiver's teardown will occur *after* the Future returned by `pop` resolves.
 If you wish to keep the context alive after the `pop` then use `pend` instead.

 @param queue the queue to chain on.
 @param pop the function to re-map the result to a new future, only called on success.
 @return a Future derived from the fmap. The teardown of the context will occur *after* this future has resolved.
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue pop:(nonnull FBFuture * _Nonnull (^)(T _Nonnull result))pop;

/**
 Continue to keep the context alive, but fmap a new future.
 The receiver's teardown will not occur after the `pend`'s Future has resolved.

 @param queue the queue to chain on.
 @param fmap the function to re-map the result to a new future, only called on success.
 @return a Context derived from the fmap.
 */
- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue pend:(nonnull FBFuture * _Nonnull (^)(T _Nonnull result))fmap;

/**
 Pushes another context.
 This can be used to make a stack of contexts that unroll once the produced context pops.

 @param queue the queue to chain on.
 @param fmap the block to produce more context.
 @return a Context derived from the fmap with the current context stacked below.
 */
- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue push:(nonnull FBFutureContext * _Nonnull (^)(T _Nonnull result))fmap;

/**
 Replaces the current context.
 This is equivalent to replacing the top of the context stack with a different context.
 @param queue the queue to chain on.
 @param replace the block to produce more context.
 @return a Context derived from the replace with the current context stacked below.
 */
- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue replace:(nonnull FBFutureContext * _Nonnull (^)(T _Nonnull result))replace;

/**
 Continue to keep the context alive, but handleError: a new future.
 The receiver's teardown will not occur after the `handleError`'s Future has resolved.

 @param queue the queue to chain on.
 @param handler the function to re-map the error to a new future, only executed if caller resolves to a failure.
 @return a Context derived from the handleError.
 */

- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue handleError:(nonnull FBFuture * _Nonnull (^)(NSError * _Nonnull))handler;

/**
 Adds a teardown to the context

 @param queue the queue to call the teardown on
 @param action the teardown action
 @return a context with the teardown applied.
 */
- (nonnull FBFutureContext *)onQueue:(nonnull dispatch_queue_t)queue contextualTeardown:(nonnull FBFuture<NSNull *> * _Nonnull (^)(T _Nonnull, FBFutureState))action;

/**
 Extracts the wrapped context, so that it can be torn-down at a later time.
 This is designed to allow a context manager to be combined with the teardown of other long-running operations.

 @param queue the queue to chain on.
 @param enter the block that receives two parameters. The first is the context value, the second is a future that will tear-down the context when it is resolved.
 @return a Future that wraps the value returned from fmap.
 */
- (nonnull FBFuture *)onQueue:(nonnull dispatch_queue_t)queue enter:(nonnull id _Nonnull (^)(T _Nonnull result, FBMutableFuture<NSNull *> * _Nonnull teardown))enter;

#pragma mark Properties

/**
 The future keeping the context alive.
 The context will not be torn down until this future resolves.
 */
@property (nonnull, nonatomic, readonly, strong) FBFuture<T> *future;

@end
