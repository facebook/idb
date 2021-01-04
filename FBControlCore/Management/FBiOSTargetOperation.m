/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetOperation.h"

#import <objc/runtime.h>

#import "FBFuture+Sync.h"

FBiOSTargetOperationType const FBiOSTargetOperationTypeApplicationLaunch = @"applaunch";

FBiOSTargetOperationType const FBiOSTargetOperationTypeAgentLaunch = @"agentlaunch";

FBiOSTargetOperationType const FBiOSTargetOperationTypeTestLaunch = @"launch_xctest";

FBiOSTargetOperationType const FBiOSTargetOperationTypeLogTail = @"logtail";
@interface FBiOSTargetOperation_Wrapper : NSObject <FBiOSTargetOperation>

@end

@implementation FBiOSTargetOperation_Wrapper

@synthesize completed = _completed;

- (instancetype)initWithCompleted:(FBFuture<NSNull *> *)completed
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _completed = completed;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return _completed;
}

@end

id<FBiOSTargetOperation> FBiOSTargetOperationFromFuture(FBFuture<NSNull *> *completed)
{
  return [[FBiOSTargetOperation_Wrapper alloc] initWithCompleted:completed];
}
