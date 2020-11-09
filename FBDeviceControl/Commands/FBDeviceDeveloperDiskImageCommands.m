/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDeveloperDiskImageCommands.h"

#import "FBAMDServiceConnection.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"

static void MountCallback(NSDictionary<NSString *, id> *callbackDictionary, id<FBDeviceCommands> device)
{
  [device.logger logFormat:@"Mount Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

@interface FBDeviceDeveloperDiskImageCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceDeveloperDiskImageCommands

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

#pragma mark FBDeveloperDiskImageCommands Implementation

static const int DiskImageAlreadyMountedCode = -402653066;  // 0xe8000076 in hex

- (FBFuture<FBDeveloperDiskImage *> *)ensureDiskImageIsMounted
{
  NSError *error = nil;
  NSOperatingSystemVersion targetVersion = [FBOSVersion operatingSystemVersionFromName:self.device.productVersion];
  FBDeveloperDiskImage *diskImage = [FBDeveloperDiskImage developerDiskImage:targetVersion logger:self.device.logger error:&error];
  if (!diskImage) {
    return [FBFuture futureWithError:error];
  }
  return [[self.device
    connectToDeviceWithPurpose:@"mount_disk_image"]
    onQueue:self.device.asyncQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (id<FBDeviceCommands> device) {
      NSDictionary *options = @{
        @"ImageSignature": diskImage.signature,
        @"ImageType": @"Developer",
      };
      int status = device.calls.MountImage(
        device.amDeviceRef,
        (__bridge CFStringRef)(diskImage.diskImagePath),
        (__bridge CFDictionaryRef)(options),
        (AMDeviceProgressCallback) MountCallback,
        (__bridge void *) (device)
      );
      if (status == DiskImageAlreadyMountedCode) {
        [device.logger logFormat:@"There is a disk image already mounted. Assuming that it is correct...."];
      }
      else if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to mount image '%@' with error 0x%x (%@)", diskImage.diskImagePath, status, internalMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:diskImage];
    }];
}

@end
