/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestManager.h"

#import "FBDeviceOperator.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerResult.h"

@interface FBTestManager ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) FBMutableFuture *terminationFuture;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithContext:(FBTestManagerContext *)context iosTarget:(id<FBiOSTarget>)iosTarget reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithContext:context
    target:iosTarget
    reporter:reporter
    logger:logger];

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
  return [self.mediator.connect
    notifyOfCancellationOnQueue:self.target.workQueue handler:^(FBFuture *_) {
      [self terminate];
    }];
}

- (FBFuture<FBTestManagerResult *> *)execute
{
  return [self.mediator.execute
    notifyOfCancellationOnQueue:self.target.workQueue handler:^(FBFuture *_) {
      [self terminate];
    }];
}

- (NSString *)description
{
  return self.mediator.description;
}

#pragma mark FBXCTestOperation

- (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeTestOperation;
}

- (void)terminate
{
  [self.mediator disconnect];
  [self.terminationFuture cancel];
}

- (BOOL)hasTerminated
{
  return self.terminationFuture.hasCompleted;
}

@end
