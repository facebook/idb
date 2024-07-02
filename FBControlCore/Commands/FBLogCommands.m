/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLogCommands.h"

#import "FBProcess.h"

@interface FBProcessLogOperation ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBProcessLogOperation

@synthesize consumer = _consumer;

- (instancetype)initWithProcess:(FBProcess *)process consumer:(id<FBDataConsumer>)consumer queue:(dispatch_queue_t)queue
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _process = process;
  _consumer = consumer;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  FBProcess *process = self.process;
  return [[[process
    exitedWithCodes:[NSSet setWithObject:@0]]
    mapReplace:NSNull.null]
    onQueue:self.queue respondToCancellation:^{
      return [process sendSignal:SIGTERM backingOffToKillWithTimeout:5 logger:nil];
    }];
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

