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

@end

@implementation FBSimulatorAgentOperation

#pragma mark Initializers

+ (instancetype)operationWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr completionFuture:(FBFuture<NSNumber *> *)completionFuture
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration stdOut:stdOut stdErr:stdErr completionFuture:completionFuture];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBAgentLaunchConfiguration *)configuration stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr completionFuture:(FBFuture<NSNumber *> *)completionFuture
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;
  _stdOut = stdOut;
  _stdErr = stdErr;

  __weak typeof(self) weakSelf = self;
  _future = [completionFuture onQueue:simulator.workQueue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
    __strong typeof(self) strongSelf = weakSelf;
    if (future.result) {
      [strongSelf processDidTerminate:future.result.intValue];
      return;
    }
    [strongSelf processWasCancelled];
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

#pragma mark Private

- (void)processDidTerminate:(int)stat_loc
{
  [self performTeardown];
  [self.simulator.eventSink agentDidTerminate:self statLoc:stat_loc];
}

- (void)processWasCancelled
{
  [self performTeardown];
  // When cancelled, the process is still alive. Therefore, the process needs to be terminated to fulfill the cancellation contract.
  [[FBProcessTerminationStrategy
    strategyWithProcessFetcher:self.simulator.processFetcher.processFetcher logger:self.simulator.logger]
    killProcess:self.process error:nil];
}

- (void)performTeardown
{
  // Return early if nothing was actually launched.
  if (!self.process) {
    return;
  }

  // Match the retain in -[FBSimulatorAgentOperation processDidLaunch]
  CFRelease((__bridge CFTypeRef)(self));

  // Tear down the other resources.
  [self.stdOut terminate];
  [self.stdErr terminate];
}

#pragma mark FBTerminationAwaitable

- (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeSimulatorAgent;
}

- (BOOL)hasTerminated
{
  return self.future == nil;
}

- (void)terminate
{
  [self.future cancel];
}

@end
