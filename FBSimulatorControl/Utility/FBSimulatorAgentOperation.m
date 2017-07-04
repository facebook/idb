/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorAgentOperation.h"

#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

FBTerminationHandleType const FBTerminationHandleTypeSimulatorAgent = @"agent";

@interface FBSimulatorAgentOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorAgentOperation

#pragma mark Initializers

+ (instancetype)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOutHandle:(nullable NSFileHandle *)stdOutHandle stdErrHandle:(nullable NSFileHandle *)stdErrHandle handler:(nullable FBAgentTerminationHandler)handler
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration stdOutHandle:stdOutHandle stdErrHandle:stdErrHandle handler:handler];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOutHandle:(nullable NSFileHandle *)stdOutHandle stdErrHandle:(nullable NSFileHandle *)stdErrHandle handler:(nullable FBAgentTerminationHandler)handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _stdOutHandle = stdOutHandle;
  _stdErrHandle = stdErrHandle;
  __weak typeof(self) weakSelf = self;
  _handler = ^(int stat_loc) {
    if (handler) {
      handler(stat_loc);
    }
    typeof(self) strongSelf = weakSelf;
    [strongSelf performTeardown:stat_loc];
  };

  return self;
}

- (void)processDidLaunch:(FBProcessInfo *)process
{
  _process = process;
}

+ (BOOL)isExpectedTerminationForStatLoc:(int)statLoc
{
  if (WIFEXITED(statLoc)) {
    return WEXITSTATUS(statLoc) == 0;
  }
  return NO;
}

#pragma mark Private

- (void)performTeardown:(int)stat_loc
{
  _handler = nil;
  [self.simulator.eventSink agentDidTerminate:self statLoc:stat_loc];
}

#pragma mark FBTerminationAwaitable

+ (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeSimulatorAgent;
}

- (BOOL)hasTerminated
{
  return self.handler == nil;
}

- (void)terminate
{
  if (self.hasTerminated || self.process == nil) {
    return;
  }
  [[FBProcessTerminationStrategy
    strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher logger:self.simulator.logger]
    killProcess:self.process error:nil];
}

@end
