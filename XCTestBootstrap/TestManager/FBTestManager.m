/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManager.h"

#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerResult.h"

@interface FBTestManager ()

@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) FBFuture<FBTestManagerResult *> *executeFuture;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (FBFuture<FBTestManager *> *)connectToTestManager:(FBTestManagerContext *)context target:(id<FBiOSTarget>)target reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithContext:context
    target:target
    reporter:reporter
    logger:logger
    testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];

  dispatch_queue_t queue = target.workQueue;
  return [[mediator
    connect]
    onQueue:queue map:^(id _) {
      return [[FBTestManager alloc] initWithMediator:mediator queue:queue];
    }];
}

- (instancetype)initWithMediator:(FBTestManagerAPIMediator *)mediator queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mediator = mediator;
  _queue = queue;

  return self;
}

- (FBFuture<FBTestManagerResult *> *)execute
{
  if (self.executeFuture) {
    return self.executeFuture;
  }
  FBTestManagerAPIMediator *mediator = self.mediator;
  _executeFuture = [self.mediator.execute
    onQueue:self.queue respondToCancellation:^{
      return [mediator disconnect];
    }];
  return self.executeFuture;
}

- (NSString *)description
{
  return self.mediator.description;
}

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return [[self execute] mapReplace:NSNull.null];
}

@end
