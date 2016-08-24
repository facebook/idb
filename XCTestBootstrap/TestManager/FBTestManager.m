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

@interface FBTestManager ()

@property (nonatomic, strong, readonly) FBTestManagerContext *context;
@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) FBTestManagerProcessInteractionOperator *processOperator;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithContext:(FBTestManagerContext *)context operator:(id<FBDeviceOperator>)deviceOperator reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerProcessInteractionOperator *processOperator = [FBTestManagerProcessInteractionOperator withDeviceOperator:deviceOperator];
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithContext:context
    deviceOperator:deviceOperator
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
  _processOperator = processOperator;

  return self;
}

#pragma mark Public

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.mediator connectTestRunnerWithTestManagerDaemonWithTimeout:timeout error:error]
      && [self.mediator executeTestPlanWithTimeout:timeout error:error];
}

- (void)disconnect
{
  [self.mediator disconnectTestRunnerAndTestManagerDaemon];
}

- (BOOL)waitUntilTestingHasFinishedWithTimeout:(NSTimeInterval)timeout
{
  return [self.mediator waitUntilTestRunnerAndTestManagerDaemonHaveFinishedExecutionWithTimeout:timeout];
}

- (NSString *)description
{
  return self.context.description;
}

@end
