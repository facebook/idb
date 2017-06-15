/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogicTestStrategy.h"

#import "FBAgentLaunchStrategy.h"

@interface FBSimulatorLogicTestStrategy ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@property (nonatomic, strong, readwrite) FBPipeReader *stdOutPipe;
@property (nonatomic, strong, readwrite) FBPipeReader *stdErrPipe;
@property (nonatomic, strong, readwrite) FBProcessInfo *process;

@property (atomic, assign, readwrite) BOOL hasTerminated;
@property (atomic, assign, readwrite) int exitCode;

@end

@implementation FBSimulatorLogicTestStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

- (pid_t)logicTestProcess:(FBLogicTestProcess *)process startWithError:(NSError **)error
{
  // Create the Pipes
  self.stdOutPipe = [FBPipeReader pipeReaderWithConsumer:process.stdOutReader];
  self.stdErrPipe = [FBPipeReader pipeReaderWithConsumer:process.stdErrReader];
  NSError *innerError = nil;

  // Start Reading the Stdout
  if (![self.stdOutPipe startReadingWithError:&innerError]) {
    [[[FBXCTestError
      describeFormat:@"Failed to read the stdout of Logic Test Process %@", process.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  // Start Reading the Stderr
  if (![self.stdErrPipe startReadingWithError:&innerError]) {
    [[[FBXCTestError
      describeFormat:@"Failed to read the stdout of Logic Test Process %@", process.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  // Launch The Process
  FBAgentLaunchHandler handler = ^(int stat_loc){
    if (WIFEXITED(stat_loc)) {
      self.exitCode = WEXITSTATUS(stat_loc);
    } else if (WIFSIGNALED(stat_loc)) {
      self.exitCode = WTERMSIG(stat_loc);
    }
    self.hasTerminated = YES;
  };
  self.process = [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator]
    launchAgentWithLaunchPath:process.launchPath
    arguments:process.arguments
    environment:process.environment
    waitForDebugger:process.waitForDebugger
    stdOut:self.stdOutPipe.pipe.fileHandleForWriting
    stdErr:self.stdErrPipe.pipe.fileHandleForWriting
    terminationHandler:handler
    error:&innerError];
  if (!self.process) {
    [[[FBXCTestError
      describeFormat:@"Failed to launch Logic Test Process %@", process.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  return self.process.processIdentifier;
}

- (void)terminateLogicTestProcess:(FBLogicTestProcess *)process
{

}

- (BOOL)logicTestProcess:(FBLogicTestProcess *)process waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  BOOL waitSuccessful = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.hasTerminated;
  }];

  // Check that we exited normally
  if (![process processDidTerminateNormallyWithProcessIdentifier:self.process.processIdentifier didTimeout:(waitSuccessful == NO) exitCode:self.exitCode error:error]) {
    return NO;
  }
  return YES;
}

@end
