/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceScreenshotCommands.h"

#import "FBDevice.h"
#import "FBDLDevice.h"

@interface FBDeviceScreenshotCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceScreenshotCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  return [[self alloc] initWithDevice:(FBDevice *)target];
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

#pragma mark FBScreenshotCommands

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [[FBDLDevice
    deviceWithUDID:self.device.udid timeout:FBControlCoreGlobalConfiguration.regularTimeout]
    onQueue:self.device.workQueue fmap:^(FBDLDevice *dlDevice) {
      return [dlDevice screenshotData];
    }];
}

@end
