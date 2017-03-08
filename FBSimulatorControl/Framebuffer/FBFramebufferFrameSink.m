/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferFrameSink.h"

@interface FBFramebufferCompositeFrameSink ()

@property (nonatomic, copy, readwrite) NSArray<id<FBFramebufferFrameSink>> *sinks;

@end

@implementation FBFramebufferCompositeFrameSink

+ (instancetype)withSinks:(NSArray<id<FBFramebufferFrameSink>> *)sinks
{
  return [[FBFramebufferCompositeFrameSink alloc] initWithSinks:sinks];
}

- (instancetype)initWithSinks:(NSArray<id<FBFramebufferFrameSink>> *)sinks
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sinks = sinks;

  return self;
}

#pragma mark FBFramebufferFrameSink Implementation

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame
{
  for (id<FBFramebufferFrameSink> delegate in self.sinks) {
    [delegate frameGenerator:frameGenerator didUpdate:frame];
  }
}

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  for (id<FBFramebufferFrameSink> delegate in self.sinks) {
    [delegate frameGenerator:frameGenerator didBecomeInvalidWithError:error teardownGroup:teardownGroup];
  }
}

@end
