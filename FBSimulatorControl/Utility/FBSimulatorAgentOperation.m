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
#import "FBProcessOutput.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

FBTerminationHandleType const FBTerminationHandleTypeSimulatorAgent = @"agent";

@interface FBSimulatorAgentOperation ()

@property (nonatomic, weak, nullable, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *mutableFuture;

@end

@implementation FBSimulatorAgentOperation

#pragma mark Initializers

+ (instancetype)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr handler:(nullable FBAgentTerminationHandler)handler
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr handler:handler];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr handler:(nullable FBAgentTerminationHandler)handler
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _stdOut = stdOut;
  _stdErr = stdErr;
  _mutableFuture = FBMutableFuture.future;
  __weak typeof(self) weakSelf = self;
  _handler = ^(int stat_loc) {
    if (handler) {
      handler(stat_loc);
    }
    typeof(self) strongSelf = weakSelf;
    [strongSelf performTeardown:stat_loc];
  };
  [_mutableFuture onQueue:simulator.workQueue notifyOfCancellation:^(FBFuture *_) {
    typeof(self) strongSelf = weakSelf;
    [strongSelf terminate];
  }];

  return self;
}

- (void)processDidLaunch:(FBProcessInfo *)process
{
  // In order to ensure that the reciever is alive as long as the process is spawned.
  // We increase the retain count, until it is torn-down.
  CFRetain((__bridge CFTypeRef)(self));
  _process = process;
}

+ (BOOL)isExpectedTerminationForStatLoc:(int)statLoc
{
  if (WIFEXITED(statLoc)) {
    return WEXITSTATUS(statLoc) == 0;
  }
  return NO;
}

- (FBFuture<NSNumber *> *)future
{
  return self.mutableFuture;
}

#pragma mark Private

- (void)performTeardown:(int)stat_loc
{
  // Return early if nothing was actually launched.
  if (!self.process) {
    return;
  }

  // Match the retain in -[FBSimulatorAgentOperation processDidLaunch]
  CFRelease((__bridge CFTypeRef)(self));

  // Tear down the other resources.
  _handler = nil;
  [self.simulator.eventSink agentDidTerminate:self statLoc:stat_loc];
  [self.stdOut terminate];
  [self.stdErr terminate];
  [self.mutableFuture resolveWithResult:@(stat_loc)];
}

#pragma mark FBTerminationAwaitable

- (FBTerminationHandleType)handleType
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
