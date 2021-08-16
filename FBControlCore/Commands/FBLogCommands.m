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

- (instancetype)initWithProcess:(FBLaunchedProcess *)process consumer:(id<FBDataConsumer>)consumer
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

+ (NSArray<NSString *> *)osLogArgumentsInsertStreamIfNeeded:(NSArray<NSString *> *)arguments
{
  NSString *firstArgument = arguments.firstObject;
  if (!firstArgument) {
    return @[@"stream"];
  }
  if ([self.osLogSubcommands containsObject:firstArgument]) {
    return arguments;
  }
  return [@[@"stream"] arrayByAddingObjectsFromArray:arguments];
}

#pragma mark Private

+ (NSSet<NSString *> *)osLogSubcommands
{
  static dispatch_once_t onceToken;
  static NSSet<NSString *> *subcommands;
  dispatch_once(&onceToken, ^{
    subcommands = [NSSet setWithArray:@[
      @"collect",
      @"config",
      @"erase",
      @"show",
      @"stream",
      @"stats",
    ]];
  });
  return subcommands;
}

@end

