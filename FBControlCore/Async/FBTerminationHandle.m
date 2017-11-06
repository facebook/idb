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

@interface FBTerminationAwaitableFuture () <FBTerminationAwaitable>

@property (nonatomic, strong, readonly) FBFuture *future;

@end

@implementation FBTerminationAwaitableFuture

@synthesize handleType = _handleType;

+ (nullable id<FBTerminationAwaitable>)awaitableFromFuture:(FBFuture *)future handleType:(FBTerminationHandleType)handleType error:(NSError **)error
{
  if (future.error) {
    if (error) {
      *error = future.error;
    }
    return nil;
  }
  return [[self alloc] initWithFuture:future handleType:handleType];
}

- (instancetype)initWithFuture:(FBFuture *)future handleType:(FBTerminationHandleType)handleType
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _future = future;
  _handleType = handleType;

  return self;
}

- (void)terminate
{
  [self.future cancel];
}

- (FBFuture *)completed
{
  return [[self future] mapReplace:NSNull.null];
}

@end
