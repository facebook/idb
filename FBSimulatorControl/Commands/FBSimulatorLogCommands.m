/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLogCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBAgentLaunchStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorAgentOperation.h"
#import "FBSimulatorError.h"

@interface FBSimulatorLogOperation : NSObject <FBLogOperation>

@property (nonatomic, strong, readonly) FBSimulatorAgentOperation *operation;

@end

@implementation FBSimulatorLogOperation

@synthesize consumer = _consumer;

- (instancetype)initWithOperation:(FBSimulatorAgentOperation *)operation consumer:(id<FBDataConsumer>)consumer
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _operation = operation;
  _consumer = consumer;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.operation.statLoc mapReplace:NSNull.null];
}

@end

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

- (FBFuture<id<FBLogOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return (FBFuture<id<FBLogOperation>> *) [[self
    startLogCommand:[@[@"stream"] arrayByAddingObjectsFromArray:arguments] consumer:consumer]
    onQueue:self.simulator.workQueue map:^(FBSimulatorAgentOperation *operation) {
      return [[FBSimulatorLogOperation alloc] initWithOperation:operation consumer:consumer];
    }];
}

#pragma mark Private

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
    output:output
    mode:FBAgentLaunchModeDefault];

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
