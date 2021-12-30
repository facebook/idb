/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetOperation.h"

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
