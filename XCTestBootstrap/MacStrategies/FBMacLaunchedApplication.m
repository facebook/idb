/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBMacLaunchedApplication.h"

#import "FBMacDevice.h"

@interface FBMacLaunchedApplication()
@property (nonatomic, strong) FBProcess *process;
@property (nonatomic, weak) FBMacDevice *device;
@property (nonatomic, assign) dispatch_queue_t queue;
@end

@implementation FBMacLaunchedApplication
@synthesize bundleID = _bundleID;
@synthesize processIdentifier = _processIdentifier;

- (instancetype)initWithBundleID:(NSString *)bundleID
               processIdentifier:(pid_t)processIdentifier
                          device:(FBMacDevice *)device
                           queue:(dispatch_queue_t)queue
{
  if (self = [super init]) {
    _bundleID = bundleID;
    _processIdentifier = processIdentifier;
    _device = device;
    _queue = queue;
  }
  return self;
}

- (FBFuture<NSNull *> *)applicationTerminated
{
  NSString *bundleID = self.bundleID;
  FBMacDevice *device = self.device;
  return [FBMutableFuture.future
    onQueue:self.queue respondToCancellation:^ FBFuture<NSNull *> *{
      return [device killApplicationWithBundleID:bundleID];
    }];
}

@end
