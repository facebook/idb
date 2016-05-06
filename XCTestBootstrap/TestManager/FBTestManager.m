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

@interface FBTestManager () <FBTestManagerProcessInteractionDelegate>

@property (nonatomic, strong, readonly) FBTestManagerAPIMediator *mediator;
@property (nonatomic, strong, readonly) id<FBDeviceOperator> deviceOperator;

@end

@implementation FBTestManager

#pragma mark Initializers

+ (instancetype)testManagerWithOperator:(id<FBDeviceOperator>)deviceOperator testRunnerPID:(pid_t)testRunnerPID sessionIdentifier:(NSUUID *)sessionIdentifier reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger
{
  FBTestManagerAPIMediator *mediator = [FBTestManagerAPIMediator
    mediatorWithDevice:deviceOperator.dvtDevice
    testRunnerPID:testRunnerPID
    sessionIdentifier:sessionIdentifier];

  FBTestManager *manager = [[self alloc] initWithMediator:mediator deviceOperator:deviceOperator];
  mediator.processDelegate = manager;
  mediator.reporter = reporter;

  return manager;
}

- (instancetype)initWithMediator:(FBTestManagerAPIMediator *)mediator deviceOperator:(id<FBDeviceOperator>)deviceOperator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mediator = mediator;
  _deviceOperator = deviceOperator;

  return self;
}

#pragma mark Public

- (BOOL)connectWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.mediator connectTestRunnerWithTestManagerDaemonWithTimeout:timeout error:error];
}

- (void)disconnect
{
  [self.mediator disconnectTestRunnerAndTestManagerDaemon];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"SessionID: %@ | Testrunner PID: %d",
    self.mediator.sessionIdentifier,
    self.mediator.testRunnerPID
  ];
}

#pragma mark - FBTestManagerMediatorDelegate

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator launchProcessWithPath:(NSString *)path bundleID:(NSString *)bundleID arguments:(NSArray *)arguments environmentVariables:(NSDictionary *)environment error:(NSError **)error
{
  if (![self.deviceOperator isApplicationInstalledWithBundleID:bundleID error:error]) {
    if (![self.deviceOperator installApplicationWithPath:path error:error]) {
      return NO;
    }
  }
  if (![self.deviceOperator launchApplicationWithBundleID:bundleID arguments:arguments environment:environment error:error]) {
    return NO;
  }
  return YES;
}

- (BOOL)testManagerMediator:(FBTestManagerAPIMediator *)mediator killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.deviceOperator killApplicationWithBundleID:bundleID error:error];
}

@end
