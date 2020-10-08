/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFuture.h"

#import "FBCollectionOperations.h"
#import "FBControlCore.h"

/**
 A String Mirror of the State.
 */
typedef NSString *FBFutureStateString NS_STRING_ENUM;
FBFutureStateString const FBFutureStateStringRunning = @"running";
FBFutureStateString const FBFutureStateStringDone = @"done";
FBFutureStateString const FBFutureStateStringFailed = @"error";
FBFutureStateString const FBFutureStateStringCancelled = @"cancelled";

static FBFutureStateString FBFutureStateStringFromState(FBFutureState state)
{
  switch (state) {
    case FBFutureStateRunning:
      return FBFutureStateStringRunning;
    case FBFutureStateDone:
      return FBFutureStateStringDone;
    case FBFutureStateFailed:
      return FBFutureStateStringFailed;
    case FBFutureStateCancelled:
      return FBFutureStateStringCancelled;
    default:
      return @"";
  }
}

dispatch_time_t FBCreateDispatchTimeFromDuration(NSTimeInterval inDuration)
{
  return dispatch_time(DISPATCH_TIME_NOW, (int64_t)(inDuration * NSEC_PER_SEC));
}

static void final_resolveUntil(FBMutableFuture *final, dispatch_queue_t queue, FBFuture *(^resolveUntil)(void)) {
    if (final.hasCompleted) {
      return;
    }
    FBFuture<id> *future = resolveUntil();
    [future onQueue:queue notifyOfCompletion:^(FBFuture<id> *resolved) {
      switch (resolved.state) {
        case FBFutureStateCancelled:
          [final cancel];
          return;
        case FBFutureStateDone:
          [final resolveWithResult:resolved.result];
          return;
        case FBFutureStateFailed:
          final_resolveUntil(final, queue, resolveUntil);
          return;
        default:
          return;
      }
    }];
}

@interface FBFuture_Handler : NSObject

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) void (^handler)(FBFuture *);

@end

@implementation FBFuture_Handler

- (instancetype)initWithQueue:(dispatch_queue_t)queue handler:(void (^)(FBFuture *))handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _handler = handler;

  return self;
}

@end

@interface FBFuture_Cancellation : NSObject

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *(^handler)(void);

@end

@implementation FBFuture_Cancellation

- (instancetype)initWithQueue:(dispatch_queue_t)queue handler:(FBFuture<NSNull *> *(^)(void))handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _handler = handler;

  return self;
}

@end

@interface FBFutureContext_Teardown : NSObject

@property (nonatomic, strong, readonly) FBFuture *future;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBFuture<NSNull *> * (^action)(id, FBFutureState);

@end

@implementation FBFutureContext_Teardown

- (instancetype)initWithFuture:(FBFuture *)future queue:(dispatch_queue_t)queue action:(FBFuture<NSNull *> * (^)(id, FBFutureState))action
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _future = future;
  _queue = queue;
  _action = action;

  return self;
}

- (FBFuture<NSNull *> *)performTeardown:(FBFutureState)endState
{
  NSAssert(self.future.state != FBFutureStateRunning, @"Performing teardown on an unresolved future is not-permitted.");
  FBFuture<NSNull *> * (^action)(id, FBFutureState) = self.action;
  FBMutableFuture<NSNull *> *teardownCompleted = FBMutableFuture.future;

  // By this point the future will actually be resolved.
  // The reason for this notifyOfCompletion, is that we can use it for the queue-bounce to the queue that the action is expected to be called on.
  [self.future onQueue:self.queue notifyOfCompletion:^(FBFuture *resolved) {
    if (resolved.result) {
      FBFuture<NSNull *> *resolvedTeardownCompleted = action(resolved.result, endState);
      [teardownCompleted resolveFromFuture:resolvedTeardownCompleted];
    } else {
      [teardownCompleted resolveWithResult:NSNull.null];
    }
  }];
  return teardownCompleted;
}

@end

@interface FBFutureContext ()

@property (nonatomic, copy, readonly) NSMutableArray<FBFutureContext_Teardown *> *teardowns;

@end

@implementation FBFutureContext

#pragma mark Initializers

+ (FBFutureContext *)futureContextWithFuture:(FBFuture *)future;
{
  return [[self alloc] initWithFuture:future teardowns:[NSMutableArray array]];
}

+ (FBFutureContext *)futureContextWithResult:(id)result
{
  return [self futureContextWithFuture:[FBFuture futureWithResult:result]];
}

+ (FBFutureContext *)futureContextWithError:(NSError *)error
{
  return [self futureContextWithFuture:[FBFuture futureWithError:error]];
}

+ (FBFutureContext<NSArray<id> *> *)futureContextWithFutureContexts:(NSArray<FBFutureContext *> *)contexts
{
  NSMutableArray<FBFuture *> *futures = NSMutableArray.array;
  NSMutableArray<FBFutureContext_Teardown *> *teardowns = NSMutableArray.array;
  for (FBFutureContext *context in contexts) {
    [futures addObject:context.future];
    [teardowns addObjectsFromArray:context.teardowns];
  }
  FBFuture<NSArray<id> *> *future = [FBFuture futureWithFutures:futures];
  return [[FBFutureContext alloc] initWithFuture:future teardowns:teardowns];
}

- (instancetype)initWithFuture:(FBFuture *)future teardowns:(NSMutableArray<FBFutureContext_Teardown *> *)teardowns
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _future = future;
  _teardowns = teardowns;

  return self;
}

#pragma mark Public

- (FBFuture *)onQueue:(dispatch_queue_t)queue pop:(FBFuture * (^)(id))pop
{
  NSArray<FBFutureContext_Teardown *> *teardowns = self.teardowns;

  return [[self.future
    onQueue:queue fmap:pop]
    onQueue:queue notifyOfCompletion:^(FBFuture *resolved) {
      [FBFutureContext popTeardowns:teardowns.reverseObjectEnumerator state:resolved.state];
    }];
}

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue pend:(FBFuture * (^)(id result))fmap
{
  FBFuture *next = [self.future onQueue:queue fmap:fmap];
  return [[FBFutureContext alloc] initWithFuture:next teardowns:self.teardowns];
}

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue push:(FBFutureContext * (^)(id))fmap
{
  __block FBFutureContext *nextContext = nil;
  FBFuture *future = [self.future onQueue:queue fmap:^(id result) {
    FBFutureContext *resolved = fmap(result);
    [nextContext.teardowns addObjectsFromArray:resolved.teardowns];
    return resolved.future;
  }];
  nextContext = [[FBFutureContext alloc] initWithFuture:future teardowns:self.teardowns];
  return nextContext;
}

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue replace:(FBFutureContext * (^)(id))replace
{
  FBFutureContext_Teardown *top = self.teardowns.lastObject;
  [self.teardowns removeLastObject];
  __block FBFutureContext *nextContext = nil;
  FBFuture *future = [[self.future
    onQueue:queue fmap:^(id result) {
      FBFutureContext *resolved = replace(result);
      [nextContext.teardowns addObjectsFromArray:resolved.teardowns];
      return resolved.future;
    }]
    onQueue:queue chain:^(FBFuture *resolved) {
      return [[top performTeardown:resolved.state] chainReplace:resolved];
    }];

  nextContext = [[FBFutureContext alloc] initWithFuture:future teardowns:self.teardowns];
  return nextContext;
}

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue contextualTeardown:( FBFuture<NSNull *> * (^)(id, FBFutureState) )action
{
  FBFutureContext_Teardown *teardown = [[FBFutureContext_Teardown alloc] initWithFuture:self.future queue:queue action:action];
  [self.teardowns addObject:teardown];
  return self;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue enter:(id (^)(id result, FBMutableFuture<NSNull *> *teardown))enter
{
  FBMutableFuture *started = FBMutableFuture.future;

  [self onQueue:queue pop:^(id contextValue){
    FBMutableFuture<NSNull *> *completed = FBMutableFuture.future;
    id mappedValue = enter(contextValue, completed);
    [started resolveWithResult:mappedValue];
    return completed;
  }];

  return started;
}

#pragma mark Private

+ (FBFuture<NSNull *> *)popTeardowns:(NSEnumerator<FBFutureContext_Teardown *> *)teardowns state:(FBFutureState)state
{
  FBFutureContext_Teardown *teardown = teardowns.nextObject;
  if (!teardown) {
    return FBFuture.empty;
  }
  return [[teardown
    performTeardown:state]
    onQueue:teardown.queue chain:^(id _) {
      return [self popTeardowns:teardowns state:state];
    }];
}

@end

@interface FBFuture ()

@property (atomic, copy, nullable, readwrite) NSString *name;
@property (nonatomic, strong, readonly) NSMutableArray<FBFuture_Handler *> *handlers;
@property (nonatomic, strong, nullable, readwrite) NSMutableArray<FBFuture_Cancellation *> *cancelResponders;
@property (nonatomic, strong, nullable, readwrite) FBFuture<NSNull *> *resolvedCancellation;

@end

@implementation FBFuture

@synthesize error = _error, result = _result, state = _state;

#pragma mark Initializers

+ (FBFuture *)futureWithResult:(id)result
{
  FBMutableFuture *future = FBMutableFuture.future;
  return [future resolveWithResult:result];
}

+ (FBFuture *)futureWithError:(NSError *)error
{
  FBMutableFuture *future = FBMutableFuture.future;
  return [future resolveWithError:error];
}

+ (FBFuture *)futureWithDelay:(NSTimeInterval)delay future:(FBFuture *)future
{
  FBMutableFuture *delayed = FBMutableFuture.future;
  dispatch_after(FBCreateDispatchTimeFromDuration(delay), FBFuture.internalQueue, ^{
    [delayed resolveFromFuture:future];
  });
  return [delayed onQueue:FBFuture.internalQueue respondToCancellation:^{
    [future cancel];
    return FBFuture.empty;
  }];
}

+ (instancetype)resolveValue:( id(^)(NSError **) )resolve
{
  NSError *error = nil;
  id result = resolve(&error);
  if (result) {
    return [FBFuture futureWithResult:result];
  } else {
    return [FBFuture futureWithError:error];
  }
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolveValue:(id(^)(NSError **))resolve;
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(queue, ^{
    NSError *error = nil;
    id result = resolve(&error);
    if (!result) {
      NSCAssert(error, @"Error must be set on nil return");
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:result];
    }
  });
  return future;
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolve:( FBFuture *(^)(void) )resolve
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(queue, ^{
    FBFuture *resolved = resolve();
    [future resolveFromFuture:resolved];
  });
  return future;
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue resolveWhen:(BOOL (^)(void))resolveWhen
{
  FBMutableFuture *future = FBMutableFuture.future;

  dispatch_async(queue, ^{
    const NSTimeInterval interval = 0.1;
    const dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(timer, FBCreateDispatchTimeFromDuration(interval), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 10));
    dispatch_source_set_event_handler(timer, ^{
      if (future.state != FBFutureStateRunning) {
        dispatch_cancel(timer);
      } else if (resolveWhen()) {
        dispatch_cancel(timer);
        [future resolveWithResult:@YES];
      }
    });

    dispatch_resume(timer);
  });

  return future;
}

+ (FBFuture<id> *)onQueue:(dispatch_queue_t)queue resolveUntil:(FBFuture<id> *(^)(void))resolveUntil
{
  FBMutableFuture *final = FBMutableFuture.future;
  dispatch_async(queue, ^{
    final_resolveUntil(final, queue, resolveUntil);
  });
  return final;
}

- (instancetype)timeout:(NSTimeInterval)timeout waitingFor:(NSString *)format, ...
{
  NSParameterAssert(timeout > 0);

  va_list args;
  va_start(args, format);
  NSString *description = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  FBFuture *timeoutFuture = [[[[FBControlCoreError
    describeFormat:@"Timed out after %f seconds waiting for %@", timeout, description]
    noLogging]
    failFuture]
    delay:timeout];
  return [FBFuture race:@[self, timeoutFuture]];
}

+ (FBFuture *)futureWithFutures:(NSArray<FBFuture *> *)futures
{
  if (futures.count == 0) {
    return [FBFuture futureWithResult:@[]];
  }

  FBMutableFuture *compositeFuture = FBMutableFuture.future;
  NSMutableArray *results = [[FBCollectionOperations arrayWithObject:NSNull.null count:futures.count] mutableCopy];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.composite", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remaining = futures.count;

  // `futureCompleted` must be called on `queue`.
  void (^futureCompleted)(FBFuture *, NSUInteger) = ^(FBFuture *future, NSUInteger index) {
    if (compositeFuture.hasCompleted) {
      return;
    }

    FBFutureState state = future.state;
    switch (state) {
      case FBFutureStateDone:
        results[index] = future.result;
        remaining--;
        if (remaining == 0) {
          [compositeFuture resolveWithResult:[results copy]];
        }
        return;
      case FBFutureStateFailed:
        [compositeFuture resolveWithError:future.error];
        return;
      case FBFutureStateCancelled:
        [compositeFuture cancel];
        return;
      default:
        NSCAssert(NO, @"Unexpected state in callback %@", FBFutureStateStringFromState(state));
        return;
    }
  };

  for (NSUInteger index = 0; index < futures.count; index++) {
    FBFuture *future = futures[index];
    if (future.hasCompleted) {
      // The reason that this is done in-line is to avoid work being
      // asynchronous when not necessary. For example a future-of-futures where
      // the input futures have resolved already should resolve immediately.
      // The dispatch_sync ensures that in this case, the composed future is
      // resolved before returning from the constructor.
      // It's OK to use dispatch_sync here: queue is local; there is no dispatch
      // calls within futureCompleted().
      // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
      dispatch_sync(queue, ^{
        futureCompleted(future, index);
      });
    } else {
      [future onQueue:queue notifyOfCompletion:^(FBFuture *innerFuture){
        futureCompleted(innerFuture, index);
      }];
    }
  }
  return compositeFuture;
}

+ (FBFuture *)race:(NSArray<FBFuture *> *)futures
{
  NSParameterAssert(futures.count > 0);

  FBMutableFuture *compositeFuture = FBMutableFuture.future;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.race", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remainingCounter = futures.count;

  void (^cancelAllFutures)(void) = ^{
    for (FBFuture *future in futures) {
      [future cancel];
    }
  };

  // `futureCompleted` must be called on `queue`.
  void (^futureCompleted)(FBFuture *future) = ^(FBFuture *future){
    remainingCounter--;
    if (future.result) {
      [compositeFuture resolveWithResult:future.result];
      cancelAllFutures();
      return;
    }
    if (future.error) {
      [compositeFuture resolveWithError:future.error];
      cancelAllFutures();
      return;
    }
    if (remainingCounter == 0) {
      [compositeFuture cancel];
    }
  };

  for (FBFuture *future in futures) {
    if (future.hasCompleted) {
      // The reason that this is done in-line is to avoid work being
      // asynchronous when not necessary. For example a future-of-futures where
      // the input futures have resolved already should resolve immediately.
      // The dispatch_sync ensures that in this case, the composed future is
      // resolved before returning from the constructor.
      // It's OK to use dispatch_sync here: queue is local; there is no dispatch
      // calls within futureCompleted()
      // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
      dispatch_sync(queue, ^{
        futureCompleted(future);
      });
    } else {
      [future onQueue:queue notifyOfCompletion:futureCompleted];
    }
  }
  return compositeFuture;
}

+ (FBFuture<NSNull *> *)empty
{
  FBMutableFuture *future = [FBMutableFuture futureWithName:@"Empty"];
  return [future resolveWithResult:NSNull.null];
}

- (instancetype)init
{
  return [self initWithName:nil];
}

- (instancetype)initWithName:(NSString *)name
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _state = FBFutureStateRunning;
  _handlers = [NSMutableArray array];
  _cancelResponders = [NSMutableArray array];

  _name = name;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  NSString *state = [NSString stringWithFormat:@"Future %@", FBFutureStateStringFromState(self.state)];
  NSString *name = self.name;
  if (name) {
    return [NSString stringWithFormat:@"%@ %@", name, state];
  }
  return state;
}

#pragma mark Cancellation

- (FBFuture<NSNull *> *)cancel
{
  @synchronized (self) {
    if (self.resolvedCancellation) {
      return self.resolvedCancellation;
    }
    if (self.state != FBFutureStateRunning) {
      return FBFuture.empty;
    }
  }
  NSArray<FBFuture_Cancellation *> *cancelResponders = [self resolveAsCancelled];
  @synchronized (self) {
    self.resolvedCancellation = [FBFuture resolveCancellationResponders:cancelResponders forOriginalName:self.name];
    return self.resolvedCancellation;
  }
}

- (instancetype)shieldCancellation
{
  @synchronized (self) {
    if (self.state != FBFutureStateRunning) {
      return self;
    }
    [self.cancelResponders removeAllObjects];
    return self;
  }
}

- (instancetype)onQueue:(dispatch_queue_t)queue respondToCancellation:(FBFuture<NSNull *> *(^)(void))handler
{
  NSParameterAssert(queue);
  NSParameterAssert(handler);

  @synchronized(self) {
    [self.cancelResponders addObject:[[FBFuture_Cancellation alloc] initWithQueue:queue handler:handler]];
    return self;
  }
}

#pragma mark Completion Notification

- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCompletion:(void (^)(FBFuture *))handler
{
  NSParameterAssert(queue);
  NSParameterAssert(handler);

  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      FBFuture_Handler *wrapper = [[FBFuture_Handler alloc] initWithQueue:queue handler:handler];
      [self.handlers addObject:wrapper];
    } else {
      dispatch_async(queue, ^{
        handler(self);
      });
    }
  }
  return self;
}

- (instancetype)onQueue:(dispatch_queue_t)queue doOnResolved:(void (^)(id))handler
{
  return [self onQueue:queue map:^(id result) {
    handler(result);
    return result;
  }];
}

#pragma mark Deriving new Futures

- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture *(^)(FBFuture *))chain
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    FBFuture *next = chain(future);
    NSCAssert([next isKindOfClass:FBFuture.class], @"chained value is not a Future, got %@", next);
    [next onQueue:queue notifyOfCompletion:^(FBFuture *final) {
      FBFutureState state = final.state;
      switch (state) {
        case FBFutureStateFailed:
          [chained resolveWithError:final.error];
          break;
        case FBFutureStateDone:
          [chained resolveWithResult:final.result];
          break;
        case FBFutureStateCancelled:
          [chained cancel];
          break;
        default:
          NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
      }
    }];
  }];
  // Chaining: 'self' References 'chained'
  // Cancellation: 'chained' references 'self'
  // Break the cycle, if weakSelf is nullified, this is fine as completion has been processed already.
  __weak typeof(self) weakSelf = self;
  return [chained onQueue:FBFuture.internalQueue respondToCancellation:^{
    [weakSelf cancel];
    return FBFuture.empty;
  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture * (^)(id result))fmap
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    if (future.error) {
      [chained resolveWithError:future.error];
      return;
    }
    if (future.state == FBFutureStateCancelled) {
      [chained cancel];
      return;
    }
    FBFuture *fmapped = fmap(future.result);
    NSCAssert([fmapped isKindOfClass:FBFuture.class], @"fmap'ped value is not a Future, got %@", fmapped);
    [fmapped onQueue:queue notifyOfCompletion:^(FBFuture *next) {
      if (next.error) {
        [chained resolveWithError:next.error];
        return;
      }
      [chained resolveWithResult:next.result];
    }];
  }];
  // Chaining: 'self' References 'chained'
  // Cancellation: 'chained' references 'self'
  // Break the cycle, if weakSelf is nullified, this is fine as completion has been processed already.
  __weak typeof(self) weakSelf = self;
  return [chained onQueue:FBFuture.internalQueue respondToCancellation:^{
    [weakSelf cancel];
    return FBFuture.empty;
  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(id result))map
{
  return [self onQueue:queue fmap:^FBFuture *(id result) {
    id next = map(result);
    return [FBFuture futureWithResult:next];
  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue handleError:(FBFuture * (^)(NSError *))handler
{
  return [self onQueue:queue chain:^(FBFuture *future) {
    return future.error ? handler(future.error) : future;
  }];
}

- (FBFuture *)mapReplace:(id)replacement
{
  return [self onQueue:FBFuture.internalQueue map:^(id _) {
    return replacement;
  }];
}

- (FBFuture *)chainReplace:(FBFuture *)replacement
{
  return [self onQueue:FBFuture.internalQueue chain:^FBFuture *(FBFuture *_) {
    return replacement;
  }];
}

- (FBFuture *)fallback:(id)replacement
{
  return [self onQueue:FBFuture.internalQueue handleError:^(NSError *_) {
    return [FBFuture futureWithResult:replacement];
  }];
}

- (FBFuture *)delay:(NSTimeInterval)delay
{
  return [FBFuture futureWithDelay:delay future:self];
}

- (FBFuture *)rephraseFailure:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self onQueue:FBFuture.internalQueue chain:^(FBFuture *future) {
    NSError *error = future.error;
    if (!error) {
      return future;
    }
    return [[[FBControlCoreError
      describe:string]
      causedBy:error]
      failFuture];
  }];
}

#pragma mark Creating Context

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue contextualTeardown:( FBFuture<NSNull *> * (^)(id, FBFutureState))action
{
  FBFutureContext_Teardown *teardown = [[FBFutureContext_Teardown alloc] initWithFuture:self queue:queue action:action];
  return [[FBFutureContext alloc] initWithFuture:self teardowns:@[teardown].mutableCopy];
}

- (FBFutureContext *)onQueue:(dispatch_queue_t)queue pushTeardown:(FBFutureContext *(^)(id))fmap
{
  NSMutableArray<FBFutureContext_Teardown *> *teardowns = NSMutableArray.array;
  FBFuture *future = [self onQueue:queue fmap:^(id value) {
    FBFutureContext *chained = fmap(value);
    for (FBFutureContext_Teardown *teardown in chained.teardowns) {
      [teardowns addObject:[[FBFutureContext_Teardown alloc] initWithFuture:chained.future queue:teardown.queue action:teardown.action]];
    }
    return chained.future;
  }];
  return [[FBFutureContext alloc] initWithFuture:future teardowns:teardowns];
}

#pragma mark Metadata

- (FBFuture *)named:(NSString *)name
{
  self.name = name;
  return self;
}

- (FBFuture *)nameFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *name = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self named:name];
}

- (FBFuture *)logCompletion:(id<FBControlCoreLogger>)logger withPurpose:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self onQueue:FBFuture.internalQueue notifyOfCompletion:^(FBFuture *resolved) {
    [logger logFormat:@"Completed %@ with state '%@'", string, resolved];
  }];
}

#pragma mark - Properties

- (BOOL)hasCompleted
{
  FBFutureState state = self.state;
  return state != FBFutureStateRunning;
}

- (NSError *)error
{
  @synchronized (self) {
    return self->_error;
  }
}

- (id)result
{
  @synchronized (self) {
    return self->_result;
  }
}

- (FBFutureState)state
{
  @synchronized (self) {
    return _state;
  }
}

- (void)setError:(NSError *)error
{
  _error = error;
}

- (void)setState:(FBFutureState)state
{
  _state = state;
}

- (void)setResult:(id)result
{
  _result = result;
}

#pragma mark FBMutableFuture Implementation

- (instancetype)resolveWithResult:(id)result
{
  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      self.result = result;
      self.state = FBFutureStateDone;
      [self fireAllHandlers];
      self.cancelResponders = nil;
    }
  }

  return self;
}

- (instancetype)resolveWithError:(NSError *)error
{
  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      self.error = error;
      self.state = FBFutureStateFailed;
      [self fireAllHandlers];
      self.cancelResponders = nil;
    }
  }
  return self;
}

- (instancetype)resolveFromFuture:(FBFuture *)future
{
  void (^resolve)(FBFuture *future) = ^(FBFuture *resolvedFuture){
    FBFutureState state = resolvedFuture.state;
    switch (state) {
      case FBFutureStateFailed:
        [self resolveWithError:resolvedFuture.error];
        return;
      case FBFutureStateDone:
        [self resolveWithResult:resolvedFuture.result];
        return;
      case FBFutureStateCancelled:
        [self cancel];
        return;
      default:
        NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
    }
  };
  if (future.hasCompleted) {
    resolve(future);
  } else {
    [future onQueue:FBFuture.internalQueue notifyOfCompletion:resolve];
  }
  return self;
}

#pragma mark Private

- (NSArray<FBFuture_Cancellation *> *)resolveAsCancelled
{
  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      self.state = FBFutureStateCancelled;
      [self fireAllHandlers];
    }
    NSArray<FBFuture_Cancellation *> *cancelResponders = self.cancelResponders;
    self.cancelResponders = nil;
    return cancelResponders;
  }
}

- (void)fireAllHandlers
{
  for (FBFuture_Handler *handler in self.handlers) {
    dispatch_async(handler.queue, ^{
      handler.handler(self);
    });
  }
  [self.handlers removeAllObjects];
}

+ (FBFuture<NSNull *> *)resolveCancellationResponders:(NSArray<FBFuture_Cancellation *> *)cancelResponders forOriginalName:(NSString *)originalName
{
  NSString *name = [NSString stringWithFormat:@"Cancellation of %@", originalName];
  if (cancelResponders.count == 0) {
    return [FBFuture.empty named:name];
  } else if (cancelResponders.count == 1) {
    FBFuture_Cancellation *cancelResponder = cancelResponders[0];
    return [[FBFuture onQueue:cancelResponder.queue resolve:cancelResponder.handler] named:name];
  } else {
    NSMutableArray<FBFuture<NSNull *> *> *futures = [NSMutableArray array];
    for (FBFuture_Cancellation *cancelResponder in cancelResponders) {
      [futures addObject:[FBFuture onQueue:cancelResponder.queue resolve:cancelResponder.handler]];
    }
    return [[[FBFuture futureWithFutures:futures] mapReplace:NSNull.null] named:name];
  }
}

+ (dispatch_queue_t)internalQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
}

#pragma mark KVO

+ (NSSet<NSString *> *)keyPathsForValuesAffectingHasCompleted
{
  return [NSSet setWithObjects:NSStringFromSelector(@selector(state)), nil];
}

@end

@implementation FBMutableFuture

- (instancetype)resolveWithError:(NSError *)error
{
  return [super resolveWithError:error];
}

- (instancetype)resolveWithResult:(id)result
{
  return [super resolveWithResult:result];
}

- (instancetype)resolveFromFuture:(FBFuture *)future
{
  return [super resolveFromFuture:future];
}

+ (FBMutableFuture *)future
{
  return [self futureWithName:nil];
}

+ (FBMutableFuture *)futureWithName:(NSString *)name
{
  return [[FBMutableFuture alloc] initWithName:name];
}

+ (FBMutableFuture *)futureWithNameFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *name = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self futureWithName:name];
}

@end
