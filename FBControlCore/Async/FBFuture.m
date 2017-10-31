/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFuture.h"

#import "FBCollectionOperations.h"
#import "FBControlCore.h"

FBFutureStateString const FBFutureStateStringRunning = @"running";
FBFutureStateString const FBFutureStateStringCompletedWithResult = @"completed_with_result";
FBFutureStateString const FBFutureStateStringCompletedWithError = @"completed_with_error";
FBFutureStateString const FBFutureStateStringCompletedWithCancellation = @"completed_with_cancellation";

FBFutureStateString FBFutureStateStringFromState(FBFutureState state)
{
  switch (state) {
    case FBFutureStateRunning:
      return FBFutureStateStringRunning;
    case FBFutureStateCompletedWithResult:
      return FBFutureStateStringCompletedWithResult;
    case FBFutureStateCompletedWithError:
      return FBFutureStateStringCompletedWithError;
    case FBFutureStateCompletedWithCancellation:
      return FBFutureStateStringCompletedWithCancellation;
  }
  return @"";
}

static dispatch_time_t FBFutureCreateDispatchTime(NSTimeInterval inDuration)
{
  return dispatch_time(DISPATCH_TIME_NOW, (int64_t)(inDuration * NSEC_PER_SEC));
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

@interface FBFuture ()

@property (nonatomic, strong, readonly) NSMutableArray<FBFuture_Handler *> *handlers;
@property (nonatomic, copy, nullable, readwrite) NSError *error;
@property (nonatomic, copy, nullable, readwrite) id result;
@property (nonatomic, assign, readwrite) FBFutureState state;

@end

@implementation FBFuture

@synthesize error = _error, result = _result, state = _state;

#pragma mark Initializers

+ (FBFuture *)futureWithResult:(id)result
{
  FBMutableFuture *future = [self new];
  return [future resolveWithResult:result];
}

+ (FBFuture *)futureWithError:(NSError *)error
{
  FBMutableFuture *future = [self new];
  return [future resolveWithError:error];
}

+ (FBFuture *)futureWithDelay:(NSTimeInterval)delay future:(FBFuture *)future
{
  FBMutableFuture *delayed = FBMutableFuture.future;
  dispatch_after(FBFutureCreateDispatchTime(delay), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [delayed resolveFromFuture:future];
  });
  return delayed;
}

+ (instancetype)onQueue:(dispatch_queue_t)queue resolveValue:(id(^)(NSError **))resolve;
{
  FBMutableFuture *future = [self new];
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
  FBMutableFuture *future = [self new];
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

    dispatch_source_set_timer(timer, FBFutureCreateDispatchTime(interval), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * NSEC_PER_SEC / 10));
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

- (FBFuture *)timedOutIn:(NSTimeInterval)timeout
{
  NSParameterAssert(timeout > 0);

  NSError *error = [FBControlCoreError timeoutErrorWithDescription:@"FBFuture"];
  FBFuture *timeoutFuture = [FBFuture futureWithDelay:timeout future:[FBFuture futureWithError:error]];
  return [FBFuture race:@[self, timeoutFuture]];
}

+ (FBFuture *)futureWithFutures:(NSArray<FBFuture *> *)futures
{
  NSParameterAssert(futures.count > 0);

  FBMutableFuture *compositeFuture = [FBMutableFuture new];
  NSMutableArray *results = [[FBCollectionOperations arrayWithObject:NSNull.null count:futures.count] mutableCopy];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.composite", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remaining = futures.count;

  void (^futureCompleted)(FBFuture *, NSUInteger) = ^(FBFuture *future, NSUInteger index) {
    if (compositeFuture.hasCompleted) {
      return;
    }

    FBFutureState state = future.state;
    switch (state) {
      case FBFutureStateCompletedWithResult:
        results[index] = future.result;
        remaining--;
        if (remaining == 0) {
          [compositeFuture resolveWithResult:[results copy]];
        }
        return;
      case FBFutureStateCompletedWithError:
        [compositeFuture resolveWithError:future.error];
        return;
      case FBFutureStateCompletedWithCancellation:
        [compositeFuture resolveAsCancelled];
        return;
      default:
        NSCAssert(NO, @"Unexpected state in callback %@", FBFutureStateStringFromState(state));
        return;
    }
  };

  for (NSUInteger index = 0; index < futures.count; index++) {
    FBFuture *future = futures[index];
    if (future.hasCompleted) {
      futureCompleted(future, index);
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

  FBMutableFuture *compositeFuture = [FBMutableFuture new];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.future.race", DISPATCH_QUEUE_SERIAL);
  __block NSUInteger remainingCounter = futures.count;

  void (^cancelAllFutures)(void) = ^{
    for (FBFuture *future in futures) {
      [future cancel];
    }
  };

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
      futureCompleted(future);
    } else {
      [future onQueue:queue notifyOfCompletion:futureCompleted];
    }
  }
  return compositeFuture;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _state = FBFutureStateRunning;
  _handlers = [NSMutableArray array];

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Future %@", FBFutureStateStringFromState(self.state)];
}

#pragma mark FBFuture

- (instancetype)cancel
{
  return [self resolveAsCancelled];
}

- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCompletion:(void (^)(FBFuture *))handler
{
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

- (instancetype)onQueue:(dispatch_queue_t)queue notifyOfCancellation:(void (^)(FBFuture *))handler
{
  return [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    if (future.state != FBFutureStateCompletedWithCancellation) {
      return;
    }
    handler(future);
  }];
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue chain:(FBFuture *(^)(FBFuture *))chain
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    if (future.state == FBFutureStateCompletedWithCancellation) {
      [chained cancel];
      return;
    }
    FBFuture *next = chain(future);
    [next onQueue:queue notifyOfCompletion:^(FBFuture *final) {
      FBFutureState state = final.state;
      switch (state) {
        case FBFutureStateCompletedWithError:
          [chained resolveWithError:final.error];
          break;
        case FBFutureStateCompletedWithResult:
          [chained resolveWithResult:final.result];
          break;
        case FBFutureStateCompletedWithCancellation:
          [chained cancel];
          break;
        default:
          NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
      }
    }];
  }];
  return chained;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue fmap:(FBFuture * (^)(id result))fmap
{
  FBMutableFuture *chained = FBMutableFuture.future;
  [self onQueue:queue notifyOfCompletion:^(FBFuture *future) {
    if (future.error) {
      [chained resolveWithError:future.error];
      return;
    }
    if (future.state == FBFutureStateCompletedWithCancellation) {
      [chained cancel];
      return;
    }
    [fmap(future.result) onQueue:queue notifyOfCompletion:^(FBFuture *next) {
      if (next.error) {
        [chained resolveWithError:next.error];
        return;
      }
      [chained resolveWithResult:next.result];
    }];
  }];
  return chained;
}

- (FBFuture *)onQueue:(dispatch_queue_t)queue map:(id (^)(id result))map
{
  return [self onQueue:queue fmap:^FBFuture *(id result) {
    id next = map(result);
    return [FBFuture futureWithResult:next];
  }];
}

- (FBFuture *)mapReplace:(id)replacement
{
  return [self onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) map:^(id _) {
    return replacement;
  }];
}

- (FBFuture *)fmapReplace:(FBFuture *)replacement
{
  return [self onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) chain:^FBFuture *(FBFuture *_) {
    return replacement;
  }];
}

- (FBFuture *)rephraseFailure:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0) chain:^(FBFuture *future) {
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
      self.state = FBFutureStateCompletedWithResult;
      [self fireAllHandlers];
    }
  }

  return self;
}

- (instancetype)resolveWithError:(NSError *)error
{
  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      self.error = error;
      self.state = FBFutureStateCompletedWithError;
      [self fireAllHandlers];
    }
  }
  return self;
}

- (instancetype)resolveAsCancelled
{
  @synchronized (self) {
    if (self.state == FBFutureStateRunning) {
      self.state = FBFutureStateCompletedWithCancellation;
      [self fireAllHandlers];
    }
  }
  return self;
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

- (instancetype)resolveFromFuture:(FBFuture *)future
{
  void (^resolve)(FBFuture *future) = ^(FBFuture *resolvedFuture){
    FBFutureState state = resolvedFuture.state;
    switch (state) {
      case FBFutureStateCompletedWithError:
        [self resolveWithError:resolvedFuture.error];
        return;
      case FBFutureStateCompletedWithResult:
        [self resolveWithResult:resolvedFuture.result];
        return;
      case FBFutureStateCompletedWithCancellation:
        [self cancel];
        return;
      default:
        NSCAssert(NO, @"Invalid State %lu", (unsigned long)state);
    }
  };
  if (future.hasCompleted) {
    resolve(future);
  } else {
    [future onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) notifyOfCompletion:resolve];
  }
  return self;
}

#pragma mark - KVO

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

+ (FBMutableFuture *)future
{
  return [FBMutableFuture new];
}

@end
