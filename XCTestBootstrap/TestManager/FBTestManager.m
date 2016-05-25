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

@interface FBTestManager ()

@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) FBTestManagerProcessInteractionOperator *processOperator;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithOperator:(id<FBDeviceOperator>)deviceOperator testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerProcessInteractionOperator *processOperator = [FBTestManagerProcessInteractionOperator withDeviceOperator:deviceOperator];
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithDevice:deviceOperator.dvtDevice
    processDelegate:processOperator
    reporter:reporter
    logger:logger
    testRunnerPID:testRunnerPID
    sessionIdentifier:sessionIdentifier];

  return [[FBTestManager alloc] initWithMediator:mediator processOperator:processOperator];
}

- (instancetype)initWithMediator:(FBTestManagerAPIMediator *)mediator processOperator:(FBTestManagerProcessInteractionOperator *)processOperator
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

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"SessionID: %@ | Testrunner PID: %d",
    self.mediator.sessionIdentifier.UUIDString,
    self.mediator.testRunnerPID
  ];
}

@end
