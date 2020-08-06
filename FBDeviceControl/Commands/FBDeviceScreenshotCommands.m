/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceScreenshotCommands.h"

#import "FBAMDServiceConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceLinkClient.h"

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

static NSString *const ScreenShotDataKey = @"ScreenShotData";

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [[[self.device
    startDeviceLinkService:@"com.apple.mobile.screenshotr"]
    onQueue:self.device.workQueue pop:^(FBDeviceLinkClient *client) {
      return [client processMessage:@{@"MessageType": @"ScreenShotRequest"}];
    }]
    onQueue:self.device.workQueue fmap:^(NSDictionary<id, id> *response) {
      NSData *screenshotData = response[ScreenShotDataKey];
      if (![screenshotData isKindOfClass:NSData.class]) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not an NSData for %@", screenshotData, ScreenShotDataKey]
          failFuture];
      }
      return [FBFuture futureWithResult:screenshotData];
    }];
}

@end
