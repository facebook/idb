/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBIPCServer.h"

#import "FBFramebufferVideo.h"
#import "FBIPCManager.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorFramebuffer.h"
#import "FBSimulatorSet.h"

@implementation FBIPCServer

#pragma mark Initializers

+ (instancetype)withSimulatorSet:(FBSimulatorSet *)set
{
  return [[self alloc] initWithSet:set];
}

- (instancetype)initWithSet:(FBSimulatorSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;

  return self;
}

// TODO: Respond to Remote Events.

@end
