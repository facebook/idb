/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLogCommands.h"

#import "FBLaunchedProcess.h"

@implementation FBProcessLogOperation

@synthesize consumer = _consumer;

- (instancetype)initWithProcess:(id<FBLaunchedProcess>)process consumer:(id<FBDataConsumer>)consumer
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _process = process;
  _consumer = consumer;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.process.statLoc mapReplace:NSNull.null];
}

@end

