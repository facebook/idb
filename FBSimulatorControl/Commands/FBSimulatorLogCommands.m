/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLogCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorError.h"

@interface FBSimulatorLogCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorLogCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

#pragma mark Public

- (FBFuture<id<FBiOSTargetContinuation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return (FBFuture<id<FBiOSTargetContinuation>> *) [self startLogCommand:[@[@"stream"] arrayByAddingObjectsFromArray:arguments] consumer:consumer];
}

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  id<FBAccumulatingBuffer> consumer = FBLineBuffer.accumulatingBuffer;
  return [[self
    runLogCommandAndWait:arguments consumer:consumer]
    onQueue:self.simulator.asyncQueue fmap:^(id _){
      NSArray<NSString *> *lines = consumer.lines;
      if (lines.count < 2) {
        return [FBFuture futureWithResult:@[]];
      }
      return [FBFuture futureWithResult:[lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]];
  }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)runLogCommandAndWait:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return [[[self
    startLogCommand:arguments consumer:consumer]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorAgentOperation *operation) {
      // Re-Map from Launch to Exit
      return [operation processStatus];
    }]
    onQueue:self.simulator.asyncQueue fmap:^(NSNumber *statLoc){
      // Check the exit code.
      int value = statLoc.intValue;
      int exitCode = WEXITSTATUS(value);
      if (exitCode != 0) {
        return [FBFuture futureWithError:[FBSimulatorError errorForFormat:@"log exited with code %d, arguments %@", exitCode, arguments]];
      }
      return [FBFuture futureWithResult:NSNull.null];
  }];
}

- (FBFuture<FBSimulatorAgentOperation *> *)startLogCommand:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  NSError *error = nil;
  FBBinaryDescriptor *binary = [self logBinaryDescriptorWithError:&error];
  if (!binary) {
    return [FBSimulatorError failFutureWithError:error];
  }
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration
    configurationWithStdOut:consumer
    stdErr:NSNull.null
    error:&error];
  if (!output) {
    return [FBSimulatorError failFutureWithError:error];
  }

  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
    configurationWithBinary:binary
    arguments:arguments
    environment:@{}
    output:output];

  return [[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchAgent:configuration];
}

- (FBBinaryDescriptor *)logBinaryDescriptorWithError:(NSError **)error
{
  NSString *path = [[[self.simulator.device.runtime.root
    stringByAppendingPathComponent:@"usr"]
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"log"];
  return [FBBinaryDescriptor binaryWithPath:path error:error];
}

@end
