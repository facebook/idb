/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTraceRecordCommands.h"

#import "FBXCTestShimConfiguration.h"
#import "FBXCTraceConfiguration.h"
#import "FBXCTraceOperation.h"
#import "FBiOSTarget.h"

@implementation FBXCTraceRecordCommands

#pragma mark initializers

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return [[self alloc] initWithTarget:target];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;

  return self;
}

#pragma mark FBXCTraceRecordCommands

- (FBFuture<FBXCTraceRecordOperation *> *)startXctraceRecord:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [[FBXCTestShimConfiguration
    sharedShimConfigurationWithLogger:logger]
    onQueue:self.target.workQueue fmap:^(FBXCTestShimConfiguration *shim) {
      return [FBXCTraceRecordOperation operationWithTarget:self.target configuration:[configuration withShim:shim] logger:logger];
  }];
}

@end
