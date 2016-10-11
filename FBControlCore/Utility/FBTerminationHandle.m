/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTerminationHandle.h"

@interface FBTerminationHandle_Block : NSObject<FBTerminationHandle>

@property (nonatomic, copy, readwrite) void(^block)(void);

@end

@implementation FBTerminationHandle_Block

- (void)terminate
{
  self.block();
}

@end

@implementation FBTerminationHandle

+ (id<FBTerminationHandle>)terminationHandleWithBlock:( void(^)(void) )block
{
  NSParameterAssert(block);

  FBTerminationHandle_Block *handle = [FBTerminationHandle_Block new];
  handle.block = block;
  return handle;
}

@end
