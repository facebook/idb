/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorDapServerCommands.h"

#import "FBSimulator.h"

@interface FBSimulatorDapServerCommand ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorDapServerCommand

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

- (FBFuture<FBProcess<id, id<FBDataConsumer>, NSString *> *> *) launchDapServer:dapPath stdIn:(FBProcessInput *)stdIn stdOut:(id<FBDataConsumer>)stdOut{
  NSString *fullPath = [self.simulator.dataDirectory stringByAppendingPathComponent:dapPath];
  return [[[[[FBProcessBuilder
              withLaunchPath:fullPath]
              withStdIn:stdIn]
              withStdOutConsumer: stdOut]
              withStdErrInMemoryAsString]
              start];
}

@end
