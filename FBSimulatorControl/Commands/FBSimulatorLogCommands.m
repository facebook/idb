/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorLogCommands.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimRuntime.h>

#import "FBSimulator+Private.h"
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

- (FBFuture<id<FBLogOperation>> *)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  return [[self
    startLogCommand:[FBProcessLogOperation osLogArgumentsInsertStreamIfNeeded:arguments] consumer:consumer]
    onQueue:self.simulator.workQueue map:^(FBProcess *process) {
      return [[FBProcessLogOperation alloc] initWithProcess:process consumer:consumer queue:self.simulator.asyncQueue];
    }];
}

#pragma mark Private

- (FBFuture<FBProcess *> *)startLogCommand:(NSArray<NSString *> *)arguments consumer:(id<FBDataConsumer>)consumer
{
  NSError *error = nil;
  NSString *launchPath = [self logExecutablePathWithError:&error];
  if (!launchPath) {
    return [FBSimulatorError failFutureWithError:error];
  }
  FBProcessIO *processIO = [[FBProcessIO alloc]
    initWithStdIn:nil
    stdOut:[FBProcessOutput outputForDataConsumer:consumer]
    stdErr:nil];

  FBProcessSpawnConfiguration *configuration = [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:launchPath
    arguments:arguments
    environment:@{}
    io:processIO
    mode:FBProcessSpawnModeDefault];

  return [self.simulator launchProcess:configuration];
}

- (NSString *)logExecutablePathWithError:(NSError **)error
{
  NSString *path = [[[self.simulator.device.runtime.root
    stringByAppendingPathComponent:@"usr"]
    stringByAppendingPathComponent:@"bin"]
    stringByAppendingPathComponent:@"log"];
  FBBinaryDescriptor *binary = [FBBinaryDescriptor binaryWithPath:path error:error];
  if (!binary) {
    return nil;
  }
  return binary.path;
}

@end
