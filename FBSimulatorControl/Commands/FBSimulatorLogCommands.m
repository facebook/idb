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

- (nullable id<FBTerminationHandle>)tailLog:(NSArray<NSString *> *)arguments consumer:(id<FBFileConsumer>)consumer error:(NSError **)error
{
  return [self runLogCommand:[@[@"stream"] arrayByAddingObjectsFromArray:arguments] consumer:consumer error:error];
}

- (FBFuture<NSArray<NSString *> *> *)logLinesWithArguments:(NSArray<NSString *> *)arguments
{
  NSError *error = nil;
  FBAccumilatingFileConsumer *consumer = FBAccumilatingFileConsumer.new;
  FBSimulatorAgentOperation *operation = [self runLogCommand:arguments consumer:consumer error:&error];
  if (!operation) {
    return [FBFuture futureWithError:error];
  }
  return [operation.future onQueue:self.simulator.asyncQueue map:^NSArray<NSString *> *(NSNumber *_) {
    // Slice off the head of the output, this is the header.
    NSArray<NSString *> *lines = consumer.lines;
    if (lines.count < 2) {
      return @[];
    }
    return [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)];
  }];
}

#pragma mark Private

- (nullable FBSimulatorAgentOperation *)runLogCommand:(NSArray<NSString *> *)arguments consumer:(id<FBFileConsumer>)consumer error:(NSError **)error
{
  FBBinaryDescriptor *binary = [self logBinaryDescriptorWithError:error];
  if (!binary) {
    return nil;
  }
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration
    configurationWithStdOut:consumer
    stdErr:NSNull.null
    error:error];
  if (!output) {
    return nil;
  }

  FBAgentLaunchConfiguration *configuration = [FBAgentLaunchConfiguration
    configurationWithBinary:binary
    arguments:arguments
    environment:@{}
    output:output];

  return [[FBAgentLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchAgent:configuration error:error];
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
