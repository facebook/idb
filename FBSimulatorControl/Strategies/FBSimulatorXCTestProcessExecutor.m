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
#import "FBSimulator.h"

@interface FBSimulatorXCTestProcessExecutor ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

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

- (FBFuture<FBXCTestProcessInfo *> *)startProcess:(FBXCTestProcess *)process processIdentifierOut:(pid_t *)processIdentifierOut
{
  NSError *error = nil;
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration
    configurationWithStdOut:process.stdOutReader
    stdErr:process.stdErrReader
    error:&error];
  if (!output) {
    return [FBFuture futureWithError:error];
  }
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:process.launchPath error:&error];
  if (!binary) {
    return [FBFuture futureWithError:error];
  }

  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
   configurationWithBinary:binary
   arguments:process.arguments
   environment:process.environment
   output:output];

  FBFuture<FBSimulatorAgentOperation *> *future = [[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchAgent:configuration];

  FBSimulatorAgentOperation *operation = [future await:&error];
  if (!operation) {
    return [FBFuture futureWithError:error];
  }

  pid_t processIdentifier = operation.process.processIdentifier;
  if (processIdentifierOut) {
    *processIdentifierOut = processIdentifier;
  }

  return [[operation future]
    onQueue:self.simulator.asyncQueue map:^(NSNumber *statLocNumber) {
      int stat_loc = statLocNumber.intValue;
      if (WIFEXITED(stat_loc)) {
        return [[FBXCTestProcessInfo alloc] initWithProcessIdentifier:processIdentifier exitCode:WEXITSTATUS(stat_loc)];
      } else {
        return [[FBXCTestProcessInfo alloc] initWithProcessIdentifier:processIdentifier exitCode:WTERMSIG(stat_loc)];
      }
    }];
}

- (NSString *)shimPath
{
  return self.configuration.shims.iOSSimulatorTestShimPath;
}

- (NSString *)queryShimPath
{
  return self.configuration.shims.iOSSimulatorTestShimPath;
}

- (dispatch_queue_t)workQueue
{
  return self.simulator.workQueue;
}

@end
