/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferCompositeDelegate.h"

@interface FBFramebufferCompositeDelegate ()

@property (nonatomic, copy, readwrite) NSArray *delegates;

@end

@implementation FBFramebufferCompositeDelegate

+ (instancetype)withDelegates:(NSArray *)delegates
{
  return [[FBFramebufferCompositeDelegate alloc] initWithDelegates:delegates];
}

- (instancetype)initWithDelegates:(NSArray *)delegates
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _delegates = delegates;

  return self;
}

#pragma mark FBFramebufferDelegate Implementation

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image count:(NSUInteger)count size:(CGSize)size
{
  for (id<FBFramebufferDelegate> delegate in self.delegates) {
    [delegate framebufferDidUpdate:framebuffer withImage:image count:count size:size];
  }
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  for (id<FBFramebufferDelegate> delegate in self.delegates) {
    [delegate framebufferDidBecomeInvalid:framebuffer error:error teardownGroup:teardownGroup];
  }
}

@end
