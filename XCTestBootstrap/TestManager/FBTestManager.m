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

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;

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

  return [[FBTestManager alloc] initWithContext:context mediator:mediator];
}

- (instancetype)initWithContext:(FBTestManagerContext *)context mediator:(FBTestManagerAPIMediator *)mediator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mediator = mediator;
  _context = context;

  return self;
}

#pragma mark Public

- (nullable FBTestManagerResult *)connectWithTimeout:(NSTimeInterval)timeout
{
  FBTestManagerResult *result = [self.mediator connectToTestManagerDaemonAndBundleWithTimeout:timeout];
  if (result) {
    return result;
  }
  return [self.mediator executeTestPlanWithTimeout:timeout];
}

- (FBTestManagerResult *)waitUntilTestingHasFinishedWithTimeout:(NSTimeInterval)timeout
{
  return [self.mediator waitUntilTestRunnerAndTestManagerDaemonHaveFinishedExecutionWithTimeout:timeout];
}

- (FBTestManagerResult *)disconnect
{
  return [self.mediator disconnectTestRunnerAndTestManagerDaemon];
}

- (NSString *)description
{
  return self.mediator.description;
}

#pragma mark FBXCTestOperation

+ (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeTestOperation;
}

- (void)terminate
{
  [self disconnect];
}

- (BOOL)hasTerminated
{
  return [self.mediator checkForResult] != nil;
}

@end
