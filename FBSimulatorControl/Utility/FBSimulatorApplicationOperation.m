/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationOperation.h"

#import "FBSimulatorEventSink.h"

@interface FBSimulatorApplicationOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, nullable, readwrite) FBDispatchSourceNotifier *notifier;

@end

@implementation FBSimulatorApplicationOperation

#pragma mark Initializers

+ (instancetype)operationWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration process:(FBProcessInfo *)process
{
  FBSimulatorApplicationOperation *operation = [[self alloc] initWithSimulator:simulator configuration:configuration process:process];
  [operation createNotifier];
  return operation;
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationLaunchConfiguration *)configuration process:(FBProcessInfo *)process
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _process = process;

  return self;
}

#pragma mark

- (void)createNotifier
{
  __weak typeof(self) weakSelf = self;
  self.notifier = [FBDispatchSourceNotifier
    processTerminationNotifierForProcessIdentifier:self.process.processIdentifier
    queue:self.simulator.workQueue
    handler:^(FBDispatchSourceNotifier *_) {
      [weakSelf.simulator.eventSink applicationDidTerminate:self expected:NO];
      weakSelf.notifier = nil;
  }];
}

@end
