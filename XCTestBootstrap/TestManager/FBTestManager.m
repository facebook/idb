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
#import "FBTestManagerProcessInteractionDelegate.h"
#import "FBTestManagerProcessInteractionOperator.h"
#import "FBTestManagerContext.h"
#import "FBTestManagerResult.h"

@interface FBTestManager ()

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) FBTestManagerProcessInteractionOperator *processOperator;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithContext:(FBTestManagerContext *)context iosTarget:(id<FBiOSTarget>)iosTarget reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerProcessInteractionOperator *processOperator = [FBTestManagerProcessInteractionOperator withIOSTarget:iosTarget];
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithContext:context
    deviceOperator:iosTarget.deviceOperator
    processDelegate:processOperator
    reporter:reporter
    logger:logger];

  return [[FBTestManager alloc] initWithContext:context mediator:mediator processOperator:processOperator];
}

- (instancetype)initWithContext:(FBTestManagerContext *)context mediator:(FBTestManagerAPIMediator *)mediator processOperator:(FBTestManagerProcessInteractionOperator *)processOperator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mediator = mediator;
  _context = context;
  _processOperator = processOperator;

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

@end
