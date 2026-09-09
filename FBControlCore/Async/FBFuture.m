/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFuture.h"

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

static void final_resolveUntil(FBMutableFuture *final, dispatch_queue_t queue, FBFuture *(^resolveUntil)(void))
{
  if (final.hasCompleted) {
    return;
  }
  FBFuture<id> *future = resolveUntil();
  [future onQueue:queue
   notifyOfCompletion:^(FBFuture<id> *resolved) {
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
       case FBFutureStateRunning:
       default:
         return;
     }
   }];
}

@interface FBFuture_Handler : NSObject

@property (nonatomic, readonly, strong) dispatch_queue_t queue;
@property (nonatomic, readonly, strong) void (^handler)(FBFuture *);

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

@property (nonatomic, readonly, strong) dispatch_queue_t queue;
@property (nonatomic, readonly, strong) FBFuture<NSNull *> *(^handler)(void);

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

@interface FBFuture ()

@property (nullable, atomic, readwrite, copy) NSString *name;
@property (nonatomic, readonly, strong) NSMutableArray<FBFuture_Handler *> *handlers;
@property (nullable, nonatomic, readwrite, strong) NSMutableArray<FBFuture_Cancellation *> *cancelResponders;
@property (nullable, nonatomic, readwrite, strong) FBFuture<NSNull *> *resolvedCancellation;

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
  dispatch_after(FBCreateDispatchTimeFromDuration(delay),
    FBFuture.internalQueue, ^{
      [delayed resolveFromFuture:future];
    });
  return [delayed onQueue:FBFuture.internalQueue
          respondToCancellation:^{
            [future cancel];
            return FBFuture.empty;
          }];
}

+ (instancetype)resolveValue:(id (^)(NSError **) )resolve
{
  NSError *error = nil;
  id result = resolve(&error);
  if (result) {
    return [FBFuture futureWithResult:result];
  } else {
    return [FBFuture futureWithError:error];
  }
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolveValue:(id (^)(NSError **))resolve;
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

+ (instancetype)onQueue:(dispatch_queue_t)queue resolve:(FBFuture *(^)(void) )resolve
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(queue, ^{
    FBFuture *resolved = resolve();
    [future resolveFromFuture:resolved];
  });
  return future;
}

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue resolveWhen:(BOOL (^)(void))resolveWhen
{
  return [self onQueue:queue
          resolveOrFailWhen:^FBFutureLoopState (NSError **errorOut) {
            if (resolveWhen()) {
              return FBFutureLoopFinished;
            } else {
              return FBFutureLoopContinue;
            }
          }];
}

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue resolveOrFailWhen:(FBFutureLoopState (^)(NSError **errorOut))resolveOrFailWhen
{
  FBMutableFuture *future = FBMutableFuture.future;

  dispatch_async(queue, ^{
    const NSTimeInterval interval = 0.1;
    const dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

    dispatch_source_set_timer(timer, FBCreateDispatchTimeFromDuration(interval), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 10));
    __weak typeof(future) weakFuture = future;
    dispatch_source_set_event_handler(timer, ^{
      __strong typeof(weakFuture) strongFuture = weakFuture;
      if (!strongFuture || strongFuture.state != FBFutureStateRunning) {
        dispatch_cancel(timer);
        return;
      }
      NSError *error = nil;
      FBFutureLoopState resolveOrFailWhenResult = resolveOrFailWhen(&error);
      switch (resolveOrFailWhenResult) {
        case FBFutureLoopContinue:
          break;
        case FBFutureLoopFailed:
          dispatch_cancel(timer);
          NSCAssert(error != nil, @"Expected error to be set when returning FBFutureLoopFailed");
          [strongFuture resolveWithError:error];
          break;
        case FBFutureLoopFinished:
          dispatch_cancel(timer);
          NSCAssert(error == nil, @"Error must be nil when returning FBFutureLoopFinished");
          [strongFuture resolveWithResult:NSNull.null];
          break;
        default:
          NSCAssert(NO, @"Unexpected loop state: %ld", (long)resolveOrFailWhenResult);
          break;
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

- (instancetype)timeout:(NSTimeInterval)timeout waitingFor:(NSString *)description
{
  NSParameterAssert(timeout > 0);

  FBFuture *timeoutFuture = [[[FBControlCoreError
                               describe:[NSString stringWithFormat:@"Timed out after %f seconds waiting for %@", timeout, description]]
                              failFuture]
                             delay:timeout];
  return [FBFuture race:@[self, timeoutFuture]];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue
{
  FBMutableFuture *future = FBMutableFuture.future;
  dispatch_async(queue, ^{
    [future resolveFromFuture:self];
  });
  return future;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue timeout:(NSTimeInterval)timeout handler:(FBFuture *(^)(void))handler
{
  return [FBFuture
          race:@[
            self,
            [[FBFuture
              futureWithDelay:timeout
              future:FBFuture.empty]
             onQueue:queue
             fmap:^(id _) {
               return handler();
             }],
          ]
  ];
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
        results[index] = future.result ?: NSNull.null;
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
      case FBFutureStateRunning:
      default:
        NSCAssert(NO, @"Unexpected state in callback %@", FBFutureStateStringFromState(state));
        return;
    }
  };

  for (NSUInteger index = 0; index < futures.count; index++) {
    FBFuture *future = futures[index];
    if (future.hasCompleted) {
      // Already-completed inputs are folded in synchronously so the composite resolves before this returns.
      // dispatch_sync is safe: `queue` is private and `futureCompleted` never dispatches.
      dispatch_sync(queue, ^{
        futureCompleted(future, index);
      });
    } else {
      [future onQueue:queue
       notifyOfCompletion:^(FBFuture *innerFuture) {
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
  void (^futureCompleted)(FBFuture *future) = ^(FBFuture *future) {
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
      // Already-completed inputs are folded in synchronously so the composite resolves before this returns.
      // dispatch_sync is safe: `queue` is private and `futureCompleted` never dispatches.
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
  @synchronized(self) {
    FBFuture<NSNull *> *resolvedCancellation = self.resolvedCancellation;
    if (resolvedCancellation) {
      return resolvedCancellation;
    }
    if (self.state != FBFutureStateRunning) {
      return FBFuture.empty;
    }
  }
  NSArray<FBFuture_Cancellation *> *cancelResponders = [self resolveAsCancelled];
  @synchronized(self) {
    FBFuture<NSNull *> *resolvedCancellation = [FBFuture resolveCancellationResponders:cancelResponders forOriginalName:self.name];
    self.resolvedCancellation = resolvedCancellation;
    return resolvedCancellation;
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

  @synchronized(self) {
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
  return [self onQueue:queue
                   map:^(id result) {
                     handler(result);
                     return result;
                   }];
}

#pragma mark Deriving new Futures

- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture *(^)(FBFuture *))chain
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue
   notifyOfCompletion:^(FBFuture *future) {
     FBFuture *next = chain(future);
     NSCAssert([next isKindOfClass:FBFuture.class], @"chained value is not a Future, got %@", next);
     [next onQueue:queue
      notifyOfCompletion:^(FBFuture *final) {
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
          case FBFutureStateRunning:
          default:
            NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
            break;
        }
      }];
   }];
  // Chaining: 'self' References 'chained'
  // Cancellation: 'chained' references 'self'
  // Break the cycle, if weakSelf is nullified, this is fine as completion has been processed already.
  __weak typeof(self) weakSelf = self;
  return [chained onQueue:FBFuture.internalQueue
          respondToCancellation:^{
            [weakSelf cancel];
            return FBFuture.empty;
          }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture *(^)(id result))fmap
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue
   notifyOfCompletion:^(FBFuture *future) {
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
     [fmapped onQueue:queue
      notifyOfCompletion:^(FBFuture *next) {
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
  return [chained onQueue:FBFuture.internalQueue
          respondToCancellation:^{
            [weakSelf cancel];
            return FBFuture.empty;
          }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(id result))map
{
  return [self onQueue:queue
                  fmap:^FBFuture *(id result) {
                    id next = map(result);
                    return [FBFuture futureWithResult:next];
                  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue handleError:(FBFuture *(^)(NSError *))handler
{
  return [self onQueue:queue
                 chain:^(FBFuture *future) {
                   return future.error ? handler(future.error) : future;
                 }];
}

- (FBFuture *)mapReplace:(id)replacement
{
  return [self onQueue:FBFuture.internalQueue
                   map:^(id _) {
                     return replacement;
                   }];
}

- (FBFuture *)chainReplace:(FBFuture *)replacement
{
  return [self onQueue:FBFuture.internalQueue
                 chain:^FBFuture *(FBFuture *_) {
                   return replacement;
                 }];
}

- (FBFuture *)fallback:(id)replacement
{
  return [self onQueue:FBFuture.internalQueue
           handleError:^(NSError *_) {
             return [FBFuture futureWithResult:replacement];
           }];
}

- (FBFuture *)delay:(NSTimeInterval)delay
{
  return [FBFuture futureWithDelay:delay future:self];
}

- (FBFuture *)rephraseFailure:(NSString *)description
{
  return [self onQueue:FBFuture.internalQueue
                 chain:^(FBFuture *future) {
                   NSError *error = future.error;
                   if (!error) {
                     return future;
                   }
                   return (FBFuture *)[[[FBControlCoreError
                                         describe:description]
                                        causedBy:error]
                                       failFuture];
                 }];
}

#pragma mark Metadata

- (FBFuture *)named:(NSString *)name
{
  self.name = name;
  return self;
}

- (FBFuture *)logCompletion:(id<FBControlCoreLogger>)logger withPurpose:(NSString *)purpose
{
  return [self onQueue:FBFuture.internalQueue
          notifyOfCompletion:^(FBFuture *resolved) {
            [logger log:[NSString stringWithFormat:@"Completed %@ with state '%@'", purpose, resolved]];
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
  @synchronized(self) {
    return self->_error;
  }
}

- (id)result
{
  @synchronized(self) {
    return self->_result;
  }
}

- (FBFutureState)state
{
  @synchronized(self) {
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
  @synchronized(self) {
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
  @synchronized(self) {
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
  void (^resolve)(FBFuture *future) = ^(FBFuture *resolvedFuture) {
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
      case FBFutureStateRunning:
      default:
        NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
        break;
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
  @synchronized(self) {
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

@end
