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

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;

@property (nonatomic, strong, nullable, readonly) FBFuture<FBTestManagerResult *> *connectFuture;
@property (nonatomic, strong, nullable, readonly) FBFuture<FBTestManagerResult *> *executeFuture;
@property (nonatomic, strong, readonly) FBMutableFuture *terminationFuture;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithContext:(FBTestManagerContext *)context iosTarget:(id<FBiOSTarget>)iosTarget reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testedApplicationAdditionalEnvironment:(NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithContext:context
    target:iosTarget
    reporter:reporter
    logger:logger
    testedApplicationAdditionalEnvironment:testedApplicationAdditionalEnvironment];

  return [[FBTestManager alloc] initWithTarget:iosTarget mediator:mediator];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target mediator:(FBTestManagerAPIMediator *)mediator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _mediator = mediator;
  _terminationFuture = [FBMutableFuture future];

  return self;
}

#pragma mark Public

- (FBFuture<FBTestManagerResult *> *)connect
{
  if (self.connectFuture) {
    return self.connectFuture;
  }
  _connectFuture = [self.mediator.connect
    onQueue:self.target.workQueue respondToCancellation:^{
      return [self teardown];
    }];
  return self.connectFuture;
}

- (FBFuture<FBTestManagerResult *> *)execute
{
  if (self.executeFuture) {
    return self.executeFuture;
  }
  _executeFuture = [self.mediator.execute
    onQueue:self.target.workQueue respondToCancellation:^{
      return [self teardown];
    }];
  return self.executeFuture;
}

- (NSString *)description
{
  return self.mediator.description;
}

#pragma mark Private

- (FBFuture<NSNull *> *)teardown
{
  [self.mediator disconnect];
  return [self.terminationFuture cancel];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeTestOperation;
}

- (FBFuture<NSNull *> *)completed
{
  return [[[self.connect
    onQueue:self.target.workQueue fmap:^FBFuture *(FBTestManagerResult *_) {
      return [self execute];
    }]
    mapReplace:NSNull.null]
    onQueue:self.target.workQueue respondToCancellation:^{
      return [self teardown];
    }];
}

@end
