/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorXCTestProcessExecutor.h"

#import <FBControlCore/FBControlCore.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulatorAgentOperation.h"

@interface FBSimulatorXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

@property (nonatomic, strong, readwrite) FBSimulatorAgentOperation *operation;

@property (atomic, assign, readwrite) int exitCode;

@end

@implementation FBSimulatorXCTestProcessExecutor

+ (instancetype)executorWithSimulator:(FBSimulator *)simulator configuration:(FBXCTestConfiguration *)configuration
{
  return [[self alloc] initWithSimulator:simulator configuration:configuration];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator configuration:(FBXCTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _configuration = configuration;

  return self;
}

- (pid_t)logicTestProcess:(FBLogicTestProcess *)process startWithError:(NSError **)error
{
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration
    configurationWithStdOut:process.stdOutReader
    stdErr:process.stdErrReader
    error:error];
  if (!output) {
    return -1;
  }
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:process.launchPath error:error];
  if (!binary) {
    return -1;
  }

  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
   configurationWithBinary:binary
   arguments:process.arguments
   environment:process.environment
   output:output];

  // Launch The Process
  FBAgentTerminationHandler handler = ^(int stat_loc){
    if (WIFEXITED(stat_loc)) {
      self.exitCode = WEXITSTATUS(stat_loc);
    } else if (WIFSIGNALED(stat_loc)) {
      self.exitCode = WTERMSIG(stat_loc);
    }
  };

  NSError *innerError = nil;
  self.operation = [[FBAgentLaunchStrategy strategyWithSimulator:self.simulator]
    launchAgent:configuration
    terminationHandler:handler
    error:&innerError];
  if (!self.operation) {
    [[[FBXCTestError
      describeFormat:@"Failed to launch Logic Test Process %@", process.launchPath]
      causedBy:innerError]
      fail:error];
    return -1;
  }

  return self.operation.process.processIdentifier;
}

- (void)terminateLogicTestProcess:(FBLogicTestProcess *)process
{

}

- (BOOL)logicTestProcess:(FBLogicTestProcess *)process waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  BOOL waitSuccessful = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return self.operation.hasTerminated;
  }];

  // Check that we exited normally
  if (![process processDidTerminateNormallyWithProcessIdentifier:self.operation.process.processIdentifier didTimeout:(waitSuccessful == NO) exitCode:self.exitCode error:error]) {
    return NO;
  }
  return YES;
}

- (NSString *)shimPath
{
  return self.configuration.shims.iOSSimulatorTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.configuration.shims.iOSSimulatorTestShimPath;
}

@end
