/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager.h"

#import "FBIDBError.h"

@interface FBDeltaUpdateManager ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, nullable, readonly) NSNumber *expiration;
@property (nonatomic, copy, nullable, readonly) NSNumber *capacity;
@property (nonatomic, copy, readonly) FBFuture *(^create)(id);
@property (nonatomic, copy, readonly) FBFuture *(^delta)(id, NSString *, BOOL *);
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (nonatomic, strong, readonly) NSMutableDictionary<NSString *, FBDeltaUpdateSession *> *sessions;

@end

@interface FBDeltaUpdateSession ()

@property (nonatomic, weak, nullable, readonly) FBDeltaUpdateManager *manager;
@property (nonatomic, strong, nullable, readwrite) id<FBiOSTargetContinuation> operation;
@property (nonatomic, copy, nullable, readonly) NSNumber *expiration;
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, readonly) FBFuture *(^delta)(id, NSString *, BOOL *);
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, strong, nullable, readwrite) FBFuture *timer;

@end

@implementation FBDeltaUpdateSession

#pragma mark Initializers

- (instancetype)initWithIdentifier:(NSString *)identifier manager:(FBDeltaUpdateManager *)manager operation:(id<FBiOSTargetContinuation>)operation expiration:(NSNumber *)expiration logger:(id<FBControlCoreLogger>)logger delta:(FBFuture *(^)(id, NSString *, BOOL *))delta queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _identifier = identifier;
  _manager = manager;
  _expiration = expiration;
  _operation = operation;
  _logger = logger;
  _delta = delta;
  _queue = queue;

  return self;
}

#pragma mark Public

- (FBFuture *)obtainUpdates
{
  __block BOOL done = NO;
  return [[FBFuture
    onQueue:self.queue resolve:^{
      [self.logger log:@"Obtaining an update"];
      return self.delta(self.operation, self.identifier, &done);
    }]
    onQueue:self.queue fmap:^(id value) {
      if (done) {
        [self.logger log:@"Update and session is done"];
        return [[self terminate] mapReplace:value];
      } else {
        [self.logger log:@"Update recieved"];
        [self restartTimer];
        return [FBFuture futureWithResult:value];
      }
    }];
}

- (FBFuture *)terminate
{
  return [[[FBFuture
    onQueue:self.queue resolve:^{
      [self.logger log:@"Cancelling in flight-operation"];
      return [self.operation.completed cancel];
    }]
    onQueue:self.queue fmap:^(id _) {
      BOOL done = YES;
      [self.logger log:@"Obtaining the final update"];
      return self.delta(self.operation, self.identifier, &done);
    }]
    onQueue:self.queue doOnResolved:^(id _) {
      [self invalidate];
    }];
}

#pragma mark Private

- (void)restartTimer
{
  [self.timer cancel];
  self.timer = nil;

  NSNumber *expiration = self.expiration;
  if (!expiration.boolValue) {
    return;
  }
  self.timer = [[FBFuture
    futureWithDelay:self.expiration.unsignedIntegerValue future:[FBFuture futureWithResult:NSNull.null]]
    onQueue:self.queue notifyOfCompletion:^(FBFuture *future) {
      if (!future.result) {
        return;
      }
      [self.logger logFormat:@"Invalidating after no update asked for in %@ seconds", expiration];
      [self invalidate];
  }];
}

- (void)invalidate
{
  [self.logger log:@"Invalidating delta session"];
  [self.operation.completed cancel];
  self.operation = nil;
  self.timer = nil;
  [self.manager.sessions removeObjectForKey:self.identifier];
}

@end

@implementation FBDeltaUpdateManager

#pragma mark Initializers

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmismatched-parameter-types"

+ (instancetype)managerWithTarget:(id<FBiOSTarget>)target name:(NSString *)name expiration:(NSNumber *)expiration capacity:(NSNumber *)capacity logger:(id<FBControlCoreLogger>)logger create:(FBFuture *(^)(id))create delta:(FBFuture * (^)(id, NSString *, BOOL *))delta
{
  NSString *queueName = [NSString stringWithFormat:@"com.facebook.idb.%@.manager", name];
  dispatch_queue_t queue = dispatch_queue_create(queueName.UTF8String, DISPATCH_QUEUE_SERIAL);
  NSString *loggerName = [NSString stringWithFormat:@"delta_manager_%@", name];
  return [[self alloc] initWithTarget:target name:name expiration:expiration capacity:capacity logger:[logger withName:loggerName] create:create delta:delta queue:queue];
}

#pragma clang diagnostic pop

- (instancetype)initWithTarget:(id<FBiOSTarget>)target name:(NSString *)name expiration:(NSNumber *)expiration capacity:(NSNumber *)capacity logger:(id<FBControlCoreLogger>)logger create:(FBFuture * (^)(id))create delta:(FBFuture * (^)(id, NSString *, BOOL *))delta queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _name = name;
  _expiration = expiration;
  _capacity = capacity;
  _create = create;
  _delta = delta;
  _queue = queue;
  _logger = logger;
  _sessions = NSMutableDictionary.dictionary;

  return self;
}

#pragma mark Public

- (FBFuture<FBDeltaUpdateSession *> *)sessionWithIdentifier:(NSString *)outer
{
  return [FBFuture onQueue:self.queue resolve:^{
    NSString *identifier = outer;
    if (!identifier && self.sessions.count == 1) {
      identifier = self.sessions.allKeys.firstObject;
      [self.logger logFormat:@"No Identifier provided, using the sole default of %@", identifier];
    }
    if (!identifier) {
      return [[FBIDBError
        describeFormat:@"Cannot obtain %@ session, no identifier provided", self.name]
        failFuture];
    }
    FBDeltaUpdateSession *session = self.sessions[identifier];
    if (!session) {
      return [[FBIDBError
        describeFormat:@"Cannot obtain %@ session for identifier %@", self.name, identifier]
        failFuture];
    }
    return [FBFuture futureWithResult:session];
  }];
}

- (FBFuture<FBDeltaUpdateSession *> *)startSession:(id)params
{
  return [FBFuture onQueue:self.queue resolve:^{
    NSNumber *capacity = self.capacity;
    if (capacity && capacity.integerValue <= self.sessions.count) {
      return [[FBIDBError
        describeFormat:@"%@ is at capacity of %lu sessions", self.name, self.sessions.count]
        failFuture];
    }

    NSString *identifier = NSUUID.UUID.UUIDString;
    [self.logger logFormat:@"Starting a session with id %@, params %@", identifier, params];
    return [self.create(params)
      onQueue:self.queue map:^(id<FBiOSTargetContinuation> operation) {
        [self.logger logFormat:@"Started %@ with %@", identifier, operation];
        NSString *loggerName = [NSString stringWithFormat:@"delta_session_%@", self.name];
        FBDeltaUpdateSession *session = [[FBDeltaUpdateSession alloc] initWithIdentifier:identifier manager:self operation:operation expiration:self.expiration logger:[self.logger withName:loggerName] delta:self.delta queue:self.queue];
        self.sessions[identifier] = session;
        return session;
      }];
  }];
}

@end
