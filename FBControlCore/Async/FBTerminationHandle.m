/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTerminationHandle.h"

#import "FBFuture.h"

@interface FBTerminationAwaitable_Renamed : NSObject <FBTerminationAwaitable>

@property (nonatomic, strong, readonly) id<FBTerminationAwaitable> awaitable;

@end

@implementation FBTerminationAwaitable_Renamed

@synthesize handleType = _handleType;

- (instancetype)initWithAwaitable:(id<FBTerminationAwaitable>)awaitable handleType:(FBTerminationHandleType)handleType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _awaitable = awaitable;
  _handleType = handleType;

  return self;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.awaitable completed];
}

- (void)terminate
{
  return [self.awaitable terminate];
}

- (FBTerminationHandleType)handleType
{
  return _handleType;
}

@end

id<FBTerminationAwaitable> FBTerminationAwaitableRenamed(id<FBTerminationAwaitable> awaitable, FBTerminationHandleType handleType)
{
  return [[FBTerminationAwaitable_Renamed alloc] initWithAwaitable:awaitable handleType:handleType];
}
