/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceScreenshotCommands.h"

#import "FBDevice.h"
#import "FBDevice+Private.h"
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
    deviceWithAMDevice:self.device.amDevice timeout:FBControlCoreGlobalConfiguration.regularTimeout]
    onQueue:self.device.workQueue fmap:^(FBDLDevice *dlDevice) {
      return [dlDevice screenshotData];
    }];
}

@end
