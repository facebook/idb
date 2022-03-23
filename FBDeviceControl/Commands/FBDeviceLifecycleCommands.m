/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceLifecycleCommands.h"

#import "FBDevice.h"
#import "FBAMDServiceConnection.h"

@interface FBDeviceLifecycleCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceLifecycleCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBLifecycleCommands Implementation

- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state
{
  return FBiOSTargetResolveState(self.device, state);
}

- (FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state
{
  return FBiOSTargetResolveLeavesState(self.device, state);
}

@end
